; rusticOS kernel sector configuration
; -----------------------------------
; Purpose:
;   Define how many 512-byte disk sectors comprise the kernel image so the
;   loader can read the complete kernel. This file allows overriding the value
;   from the build system and performs basic sanity checks to prevent common
;   boot failures (e.g., loading too few sectors resulting in a reboot loop).
;
; How to override / provide value:
;   - Preferred: pass the kernel size in bytes and let this file compute sectors:
;       nasm ... -D KERNEL_SIZE_BYTES=<bytes>
;   - Or pass the exact sector count via the assembler command line:
;       nasm ... -D KERNEL_SECTORS=<sectors>
;   - You can also define LOADER_MAX_SECTORS to assert an upper bound used by
;     your loader logic.
;
; Notes:
;   - Sector size defaults to 512 bytes unless SECTOR_SIZE is set.
;   - If neither KERNEL_SECTORS nor KERNEL_SIZE_BYTES is provided, this file
;     falls back to a conservative default and emits a warning. Update your
;     build to provide an accurate value to avoid partial loads.

%ifndef __RUSTICOS_KERNEL_SECTORS_INC__
%define __RUSTICOS_KERNEL_SECTORS_INC__ 1

; Configurable sector size (bytes)
%ifndef SECTOR_SIZE
%assign SECTOR_SIZE 512
%endif

; Derive KERNEL_SECTORS if not already provided by the build
%ifndef KERNEL_SECTORS
    %ifdef KERNEL_SIZE_BYTES
        ; Round up: sectors = (size + (SECTOR_SIZE-1)) / SECTOR_SIZE
        %assign KERNEL_SECTORS ((KERNEL_SIZE_BYTES + (SECTOR_SIZE - 1)) / SECTOR_SIZE)
    %else
        %warning "KERNEL_SECTORS not provided; falling back to default of 11 sectors. Define -D KERNEL_SECTORS=<n> or -D KERNEL_SIZE_BYTES=<bytes> to avoid partial kernel loads."
        %assign KERNEL_SECTORS 11
    %endif
%endif

; Sanity checks
%if KERNEL_SECTORS < 1
    %error "KERNEL_SECTORS must be >= 1"
%endif

%ifdef LOADER_MAX_SECTORS
    %if KERNEL_SECTORS > LOADER_MAX_SECTORS
        %error "KERNEL_SECTORS exceeds LOADER_MAX_SECTORS expected by the loader"
    %endif
%endif

; Project-scoped alias to reduce name collisions while keeping backward compat
%ifndef RUSTICOS_KERNEL_SECTORS
%assign RUSTICOS_KERNEL_SECTORS KERNEL_SECTORS
%endif

%endif ; __RUSTICOS_KERNEL_SECTORS_INC__