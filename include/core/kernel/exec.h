#ifndef VFS_ELF_RUNNER_H
#define VFS_ELF_RUNNER_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint64_t entry_point;
    uint64_t stack_top;
    uint64_t heap_start;
    uint64_t pid;
    bool is_running;
} process_info_t;

int vfs_run_elf(const char* path, char* argv[], char* envp[]);

int vfs_run_elf_simple(const char* path);

process_info_t* vfs_get_current_process(void);

#endif // VFS_ELF_RUNNER_H