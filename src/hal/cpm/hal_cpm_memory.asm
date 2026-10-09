;==============================================================================
; HAL_CPM_MEMORY.ASM: Hardware Abstraction Layer - CP/M & RomWBW Memory Driver
;
; Purpose:
;   Implements Far RAM memory management, hardware detection, and RomWBW
;   HBIOS bank switching services for Profile 1 (Standard CP/M 2.2 / 3.0).
;
; Part of SE.COM / ZX Spectrum Next Modular Screen Editor Architecture
;==============================================================================

;------------------------------------------------------------------------------
; HAL Memory & Far Banking API Entry Points
;------------------------------------------------------------------------------
HAL_MEM_INIT		EQU	INIT_FAR_RAM_BANKS
HAL_MEM_DETECT		EQU	HBIOS_DETECT
HAL_MEM_READ_SLOT	EQU	READ_FAR_SLOT
HAL_MEM_WRITE_SLOT	EQU	WRITE_FAR_SLOT
