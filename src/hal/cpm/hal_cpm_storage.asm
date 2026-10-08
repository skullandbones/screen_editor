;==============================================================================
; HAL_CPM_STORAGE.ASM: Hardware Abstraction Layer - CP/M BDOS File Storage
;
; Purpose:
;   Implements CP/M BDOS file operations, sequential/random FCB record I/O,
;   DMA transfer setup, and user area management for Profile 1 (CP/M 2.2 / 3.0).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Storage & File I/O API Entry Points
;------------------------------------------------------------------------------
HAL_STORAGE_OPEN	EQU	LOAD_FILE
HAL_STORAGE_MAKE	EQU	CREATE_SWAP_FILE
HAL_STORAGE_CLOSE	EQU	CLEANUP_SWAP_FILE
