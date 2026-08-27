;==============================================================================
; Large Z80 Assembly Test File for SE.COM Tab & Far Memory Verification
;==============================================================================

	.ORG	$0100

START:
	LD	A, 0		; Initialize accumulator
	LD	B, 100		; Loop counter 100 iterations
LOOP:
	ADD	A, B		; Accumulate sum
	DJNZ	LOOP		; Decrement B and loop until zero

	; Display result
	LD	DE, STR_DONE
	LD	C, 9
	CALL	5
	RET

STR_DONE:
	.DB	"Computation completed successfully.", 13, 10, "$"

	.END
