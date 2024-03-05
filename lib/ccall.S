	.global	ccall1, ccall2, ccall3

ccall1:
	movq	8(%rsp),	%rdi
	jmp	*16(%rsp)

ccall2:
	movq	16(%rsp),	%rdi
	movq	8(%rsp),	%rsi
	jmp	*24(%rsp)

ccall3:
	movq	24(%rsp),	%rdi
	movq	16(%rsi),	%rdi
	movq	8(%rsi),	%rdx
	jmp	*32(%rsp)
