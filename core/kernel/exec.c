#include <core/kernel/elf_parser.h>
#include <core/kernel/mem.h>
#include <core/kernel/kstd.h>
#include <core/kernel/log.h>
#include <core/fs/vfs.h>

typedef struct {
    uint64_t entry_point;
    uint64_t stack_top;
    uint64_t heap_start;
    uint64_t pid;
    bool is_running;
} process_info_t;

#define PROCESS_STACK_SIZE (64 * 1024)
static uint8_t process_stack[PROCESS_STACK_SIZE] __attribute__((aligned(16)));

static process_info_t current_process = {0};

int vfs_run_elf(const char* path, char* argv[], char* envp[]) {
    if (!vfs_exists(path)) {
        LOG_DEBUG("File not found: %s\n", path);
        return -1;
    }

    if (vfs_is_dir(path)) {
        LOG_DEBUG("Cannot execute directory: %s\n", path);
        return -2;
    }

    int fd = vfs_open(path, VFS_READ);
    if (fd < 0) {
        LOG_DEBUG("Failed to open file: %s (error: %d)\n", path, fd);
        return -3;
    }

    vfs_off_t file_size = vfs_seek(fd, 0, VFS_SEEK_END);
    vfs_seek(fd, 0, VFS_SEEK_SET);

    if (file_size <= 0) {
        LOG_DEBUG("Empty file or seek error: %s\n", path);
        vfs_close(fd);
        return -4;
    }

    uint8_t* elf_data = kmalloc(file_size);
    if (!elf_data) {
        LOG_DEBUG("Failed to allocate memory for ELF: %lu bytes\n", file_size);
        vfs_close(fd);
        return -5;
    }

    vfs_ssize_t bytes_read = vfs_readfd(fd, elf_data, file_size);
    vfs_close(fd);
    
    if (bytes_read != file_size) {
        LOG_DEBUG("Failed to read entire file: read %ld of %ld bytes\n", 
                  bytes_read, file_size);
        kfree(elf_data);
        return -6;
    }

    if (!elf_validate(elf_data, file_size)) {
        LOG_DEBUG("Invalid ELF file: %s\n", path);
        kfree(elf_data);
        return -7;
    }

    program_info_t prog_info;
    if (elf_get_program_info(elf_data, file_size, &prog_info) < 0) {
        LOG_DEBUG("Failed to get ELF program info: %s\n", path);
        kfree(elf_data);
        return -8;
    }

    LOG_DEBUG("ELF Info for %s:\n", path);
    LOG_DEBUG("  Entry point: 0x%lx\n", prog_info.entry_point);
    LOG_DEBUG("  Text: 0x%lx-0x%lx (%lu bytes)\n",
              prog_info.text_start,
              prog_info.text_start + prog_info.text_size,
              prog_info.text_size);
    LOG_DEBUG("  Data: 0x%lx-0x%lx (%lu bytes)\n",
              prog_info.data_start,
              prog_info.data_start + prog_info.data_size,
              prog_info.data_size);
    LOG_DEBUG("  BSS: 0x%lx-0x%lx (%lu bytes)\n",
              prog_info.bss_start,
              prog_info.bss_start + prog_info.bss_size,
              prog_info.bss_size);

    uint16_t phnum = elf_get_phnum64(elf_data);
    uint64_t min_vaddr = UINT64_MAX;
    uint64_t max_vaddr = 0;

    for (uint16_t i = 0; i < phnum; i++) {
        elf64_phdr_t* phdr = elf_get_phdr64(elf_data, i);
        if (phdr && phdr->p_type == PT_LOAD) {
            if (phdr->p_vaddr < min_vaddr) {
                min_vaddr = phdr->p_vaddr;
            }
            uint64_t segment_end = phdr->p_vaddr + phdr->p_memsz;
            if (segment_end > max_vaddr) {
                max_vaddr = segment_end;
            }
        }
    }

    if (min_vaddr == UINT64_MAX || max_vaddr == 0) {
        LOG_DEBUG("No loadable segments found\n");
        kfree(elf_data);
        return -8;
    }

    uint64_t total_size = max_vaddr - min_vaddr;

    total_size = (total_size + 0xFFF) & ~0xFFF;

    LOG_DEBUG("ELF memory range: 0x%lx - 0x%lx (%lu bytes)\n", min_vaddr, max_vaddr, total_size);

    void* load_addr = kmalloc(total_size);
    if (load_addr) {
        uintptr_t addr = (uintptr_t)load_addr;
        uintptr_t aligned_addr = (addr + 0xFFF) & ~0xFFF;

        if (aligned_addr != addr) {
            kfree(load_addr);
            load_addr = kmalloc(total_size + 0x1000);
            if (load_addr) {
                aligned_addr = ((uintptr_t)load_addr + 0xFFF) & ~0xFFF;
            }
        }
        load_addr = (void*)aligned_addr;
    }
    if (!load_addr) {
        LOG_DEBUG("Failed to allocate %lu bytes for program\n", total_size);
        kfree(elf_data);
        return -9;
    }

    memset(load_addr, 0, total_size);

    int load_result = elf_load_program_relative(load_addr, min_vaddr, elf_data, file_size);
    kfree(elf_data);

    if (load_result < 0) {
        LOG_DEBUG("Failed to load ELF program\n");
        kfree(load_addr);
        return -10;
    }

    uint8_t* stack_top = process_stack + PROCESS_STACK_SIZE;

    stack_top = (uint8_t*)((uintptr_t)stack_top & ~0xF);

    uint64_t* stack = (uint64_t*)stack_top;

    int argc = 0;
    int envc = 0;
    size_t total_strings_size = 0;

    if (argv) {
        while (argv[argc]) {
            total_strings_size += strlen(argv[argc]) + 1; // +1 для '\0'
            argc++;
        }
    }

    if (envp) {
        while (envp[envc]) {
            total_strings_size += strlen(envp[envc]) + 1; // +1 для '\0'
            envc++;
        }
    }

    total_strings_size = (total_strings_size + 7) & ~7;

    uint8_t* strings_area = (uint8_t*)stack - total_strings_size;
    uint8_t* strings_ptr = strings_area;

    uint64_t* argv_ptrs[argc + 1];
    for (int i = 0; i < argc; i++) {
        argv_ptrs[i] = (uint64_t*)strings_ptr;
        strcpy((char*)strings_ptr, argv[i]);
        strings_ptr += strlen(argv[i]) + 1;
    }
    argv_ptrs[argc] = NULL;

    uint64_t* envp_ptrs[envc + 1];
    for (int i = 0; i < envc; i++) {
        envp_ptrs[i] = (uint64_t*)strings_ptr;
        strcpy((char*)strings_ptr, envp[i]);
        strings_ptr += strlen(envp[i]) + 1;
    }
    envp_ptrs[envc] = NULL;

    stack = (uint64_t*)strings_area;

    for (int i = envc; i >= 0; i--) {
        stack--;
        *stack = (uint64_t)envp_ptrs[i];
    }

    for (int i = argc; i >= 0; i--) {
        stack--;
        *stack = (uint64_t)argv_ptrs[i];
    }

    stack--;
    *stack = argc;

    uint64_t stack_pointer = (uint64_t)stack;

    current_process.entry_point = prog_info.entry_point - min_vaddr + (uint64_t)load_addr;
    current_process.stack_top = stack_pointer;
    current_process.heap_start = (uint64_t)load_addr + total_size;
    current_process.is_running = true;
    
    LOG_DEBUG("Process loaded successfully!\n");
    LOG_DEBUG("  Load address: 0x%p\n", load_addr);
    LOG_DEBUG("  Stack pointer: 0x%lx\n", stack_pointer);
    LOG_DEBUG("  Heap start: 0x%lx\n", current_process.heap_start);

    LOG_DEBUG("Jumping to entry point: 0x%lx\n", current_process.entry_point);
    LOG_DEBUG("Stack pointer: 0x%lx\n", current_process.stack_top);

    typedef void (*program_entry_t)(void);

    program_entry_t program_entry = (program_entry_t)current_process.entry_point;

    uint64_t saved_rsp;
    asm volatile ("movq %%rsp, %0" : "=r"(saved_rsp));

    asm volatile ("movq %0, %%rsp" : : "r"(current_process.stack_top));

    program_entry();

    asm volatile ("movq %0, %%rsp" : : "r"(saved_rsp));

    LOG_DEBUG("Program returned to kernel\n");

    current_process.is_running = false;

    return 0;
}

int vfs_run_elf_simple(const char* path) {
    char* argv[] = {(char*)path, NULL};
    char* envp[] = {"PATH=/bin", NULL};
    
    return vfs_run_elf(path, argv, envp);
}

process_info_t* vfs_get_current_process(void) {
    return current_process.is_running ? &current_process : NULL;
}