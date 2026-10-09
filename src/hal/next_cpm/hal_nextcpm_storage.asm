;==============================================================================
; HAL_NEXTCPM_STORAGE.ASM: Hardware Abstraction Layer - NextCPM File Storage
;
; Purpose:
;   Implements file operations, sequential/random FCB record I/O, and DMA
;   transfers for Profile 2 (CP/M on ZX Spectrum Next / NextCPM).
;   Utilizes CP/M BDOS services operating over NextCPM SD card drive images.
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Storage & File I/O API Entry Points
;------------------------------------------------------------------------------
HAL_STORAGE_OPEN	EQU	LOAD_FILE
HAL_STORAGE_MAKE	EQU	CREATE_SWAP_FILE
HAL_STORAGE_CLOSE	EQU	CLEANUP_SWAP_FILE
