/* This file is based on code from the NovariaOS project. 
The source code in NovariaOS is licensed under GPLv3. In this project, the file is available under the MIT license. 
See LICENSE in the root of the repository. 

https://github.com/novariaos/novariaos-src
*/

#include <core/kernel/kstd.h>
#include <core/kernel/mem.h>
#include <core/kernel/nvm/nvm.h>
#include <core/kernel/nvm/caps.h>
#include <core/drivers/serial.h>
#include <core/kernel/vge/fb.h>
#include <core/drivers/timer.h>
#include <core/drivers/keyboard.h>
#include <core/drivers/cdrom.h>
#include <core/kernel/log.h>
#include <core/fs/iso9660.h>
#include <core/fs/vfs.h>
#include <lib/logo.h>
#include <stddef.h>
#include <stdbool.h>
#include <lib/limine.h>
#include <core/kernel/exec.h>

static volatile struct limine_module_request module_request = {
    .id = { LIMINE_COMMON_MAGIC, 0x3e7e279702be32af, 0xca1c4f3bd1280cee },
    .revision = 0
};

static volatile struct limine_rsdp_request rsdp_request = {
    .id = { LIMINE_COMMON_MAGIC, 0xc5e77b6b397e7b43, 0x27637845accdcf3c },
    .revision = 0
};

static volatile struct limine_bootloader_info_request bootloader_info_request = {
    .id = { LIMINE_COMMON_MAGIC, 0xf55038d8e2a1202f, 0x279426fcf5f59740 },
    .revision = 0
};

static volatile struct limine_executable_address_request kernel_address_request = {
    .id = { LIMINE_COMMON_MAGIC, 0x71ba76863cc55f63, 0xb2644a48c516a487 },
    .revision = 0
};

static volatile struct limine_mp_request smp_request = {
    .id = { LIMINE_COMMON_MAGIC, 0x95a67b819a1b857e, 0xa0b61b723b6a73e0 },
    .revision = 0,
    .flags = 0
};

static volatile struct limine_paging_mode_request paging_mode_request = {
    .id = { LIMINE_COMMON_MAGIC, 0x95c1a0edab0944cb, 0xa4e5cb3842f7488a },
    .revision = 0
};

void limine_smp_entry(struct limine_mp_info *info) {
    // This function is called on each additional CPU
    // For now, just halt the CPU
    while (1) {
        asm volatile("hlt");
    }
}

void kmain() {
    kprint(":: Initializing memory manager...\n", 7);
    initializeMemoryManager();

    init_serial();
    vfs_init();
    syslog_init();
    keyboard_init();
    
    cdrom_init();
    
    void* iso_location = NULL;
    size_t iso_size = 0;
    
    if (module_request.response != NULL && module_request.response->module_count > 0) {
        LOG_DEBUG("Checking Limine modules...\n");

        for (uint64_t i = 0; i < module_request.response->module_count; i++) {
            struct limine_file *module = module_request.response->modules[i];
            LOG_DEBUG("Module %d: size=%d\n", i, module->size);

            // Check for ISO9660 filesystem
            if (module->size > 0x8005) {
                char* sig = (char*)module->address + 0x8001;
                if (sig[0] == 'C' && sig[1] == 'D' && sig[2] == '0' &&
                    sig[3] == '0' && sig[4] == '1') {
                    iso_location = (void*)module->address;
                    iso_size = module->size;
                    LOG_DEBUG("Found ISO9660 in module %d\n", i);
                    continue;
                }
            }
        }
    }
    
    if (iso_location) {
        cdrom_set_iso_data(iso_location, iso_size);
        iso9660_init(iso_location, iso_size);
        LOG_DEBUG("ISO9660 filesystem mounted\n");

        iso9660_mount_to_vfs("/", "/");
        LOG_DEBUG("ISO contents mounted to /\n");

        LOG_DEBUG("Checking mounted files...\n");
        vfs_list();
 
        init_vge_font();
        clear_screen();
    } else {
        LOG_DEBUG(":: ISO9660 filesystem not found\n");
    }

    draw_logo_row(logo, LOGO_HEIGHT, LOGO_WIDTH, NULL);

    kprint("\n\n\n\n\n\n\n\n", 15);
    kprint(":: Base kernel initialization comeplete\n", 7);

    int result = vfs_run_elf_simple("/bin/test");
    
    if (result == 0) {
        LOG_INFO("Program started successfully\n");
    } else {
        LOG_ERROR("Failed to start program: error %d\n", result);
    }
}