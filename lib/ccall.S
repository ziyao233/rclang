	.global	ccall1, ccall2, ccall3

ccall1:
	movq	8(%rsp),	%rdi
	call	*16(%rsp)
	ret

ccall2:
	movq	16(%rsp),	%rdi
	movq	8(%rsp),	%rsi
	call	*24(%rsp)
	ret

ccall3:
	movq	24(%rsp),	%rdi
	movq	16(%rsi),	%rdi
	movq	8(%rsi),	%rdx
	call	*32(%rsp)
	ret
