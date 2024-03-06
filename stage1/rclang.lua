#!/usr/bin/env lua5.4
--[[
--	rclang stage 1 compiler
--	By MIT License.
--	Copyright (c) 2023 Ziyao.
--]]

local io		= require "io";
local string		= require "string";
local math		= require "math";

local gConf = {
			debug	= false,
			pie	= true,
	      };

--[[	The lexer	]]
local gSource, gLook, gPos;
local gSingleOpList <const> = {'?',':',',','|','^','&','+','-','*','/','%',
			       '(',')',';','{','}','>','<','!','=','[',']',
			       '$'};
local gSingleOp = {};
for _, c in pairs(gSingleOpList)
do
	gSingleOp[c] = true;
end
local gKeywordList <const> = {"for", "fn", "if", "else", "dcl",
			      "ret", "break", "export", "szo"};
local gKeyword = {};
for _, keyword in pairs(gKeywordList)
do
	gKeyword[keyword] = true;
end
local gType <const> =
	{
		ptr	= { size = 8,	signed = false	},
		val	= { size = 8,	signed = false	},
		sal	= { size = 8,	signed = true	},
		u8	= { size = 1,	signed = false	},
		s8	= { size = 1,	signed = true	},
		u16	= { size = 2,	signed = false	},
		s16	= { size = 2,	signed = true	},
		u32	= { size = 4,	signed = false	},
		s32	= { size = 4,	signed = true	},
		u64	= { size = 8,	signed = false	},
		s64	= { size = 8,	signed = true	},
	};
local gMainRegister = { [1] = "%al", [2] = "%ax",
			[4] = "%eax", [8] =  "%rax" };

local function
report(msg, ...)
	local line = 1;
	for _ in gSource:sub(1, gPos):gmatch('\n')
	do
		line = line + 1;
	end
	error("At line " .. line .. ": " ..msg:format(...));
end

local function
next()
	gPos = gSource:match("()%S",gPos);
	if not gPos
	then
		gLook = { type = "EOF" };
		return;
	end
	local c,n = gSource:sub(gPos, gPos), gSource:sub(gPos + 1, gPos + 1);

	if (c == '=' or c == '!' or c == '>' or c == '<') and n == '='
	then
		gPos = gPos + 2;
		gLook = { type = c .. '=' };
	elseif (c == '>' or c == '<') and n == c
	then
		gPos = gPos + 2;
		gLook = { type = c .. n };
	elseif gSingleOp[c]
	then
		gPos = gPos + 1;
		gLook = { type = c };
	elseif not c
	then
		gLook = nil;
	elseif c:match("[%d]")
	then
		local sNum;
		sNum,gPos = gSource:match((c == '0' and n == 'x') and
					      "(0x[%dabcdef]+)()" or
					      "(%d+)()",
					  gPos);
		if gSource:sub(gPos, gPos) == 'u'
		then
			gPos = gPos + 1;
			gLook = {
					type	= "integer",
					value 	= tonumber(sNum),
				};
		else
			gLook =  {
					type	= "signed-integer",
					value	= tonumber(sNum),
				 };
		end
	elseif c:match("[%a_]")
	then
		local id;
		id, gPos = gSource:match("([%w_]+)()",gPos);

		if gType[id]
		then
			gLook = {
					type	= "type",
					info	= id,
				};
		elseif gKeyword[id]
		then
			gLook = { type = id };
		else
			gLook = {
					type	= "id",
					id	= id,
				};
		end
	else
		report("Unrecognised character %s", c);
	end
	return gLook;
end

local function
match(type, msg)
	if gLook.type ~= type
	then
		report("Expected %s, got %s", msg or type, gLook.type);
	end
	local tok = gLook;
	next();
	return tok;
end

local function
unexpected()
	report(("Unexpected token '%s'"):format(gLook.type));
end

local function
lexerInit(path)
	gSource = assert(io.open(path)):read("a");
	gLook,gIndex = "", 1;
	next();
end

local gOutputFile;
local function
codegenInit(path)
	gOutputFile = path and assert(io.open(path, "w")) or io.stdout;
	gLabelCount = 0;
end

local function
emit(s)
	gOutputFile:write("\t" .. s .. "\n");
end

local function
emitLabel(l)
	gOutputFile:write(l .. ":\n");
end

local function
getLocalLabel()
	gLabelCount = gLabelCount + 1;
	return ".L" .. (gLabelCount - 1);
end

--[[
--	Symbol Table:
--	- Indexed by symbol name
--	- @totalSize:	TOtal size of all local variables
--	- @thisSize:	Total size of variables defined in this block
--
--	Symbol Properties
--	  o type	type name, "function" for functions
--	  o static	is it stored in bss
--	  o offset	For dynamic variables. Offset from %ebp
--	  o global	will it be exported?
--	  o imported	Is it defined in other object files?
--]]

local function
printSymtab(symtab)
	if not gConf.debug
	then
		return;
	end
	io.stderr:write("\n====Symbol Table====\n");
	for name,sym in pairs(symtab)
	do
		io.stderr:write(("%s:\ttype=%s, static=%q\n"):
				format(name, sym.type, sym.static or false));
	end

	io.stderr:write("\n\n");
end

local function
deriveSymtab(outside)
	return setmetatable({},{
				__index = outside,
			       }
			   );
end

local pFuncDef, pStatement, pFuncCall, pValue;
local pFactor, pTerm, pExpr, pShift, pRelation, pEquality;
local pNot, pAnd, pOr;

local function
checkSym(symtab, id)
	if not symtab[id]
	then
		report("Undefined symbol " .. id);
	end
	return symtab[id];
end

local function
getSymAddress(name, sym)
	if sym.type == "function" or sym.static
	then
		if gConf.pie and sym.type ~= "function"
		then
			return name .. '(%rip)';
		elseif gConf.pie and sym.type == "function"
		then
			return name .. "@GOTPCREL(%rip)"
		else
			return name;
		end
	else
		return ("%d(%%rbp)"):format(sym.offset);
	end
end

--[[
--	Parse and gencode for addressing
--
--	type:	Location type
--	action:	Function to call after the target address is computed
--
--	Return:
--		Size of result in bytes
--		Scale from %rbx
--]]
local function
doAddressing(symtab, type, action)
	local ts = gType[type].size;
	match '(';
	pValue(symtab);
	match ')';
	emit "pushq	%rax";

	local scale = "";
	if gLook.type == '['
	then
		scale = ", %rdx, " .. ts;
		match '[';
		pValue(symtab);
		match ']';

		if action
		then
			emit "pushq	%rax";
		else
			emit "movq	%rax,	%rdx"
		end
	end

	if action
	then
		action();
	end

	if scale ~= "" and action
	then
		emit "popq	%rdx";
	end

	emit("popq	%rbx");

	return ts, scale;
end

local function
doCast(dest, src)
	if gType[dest].size <= gType[src].size
	then
		return;
	elseif gType[src].size == 4 and gType[dest].size == 8 and
	       not gType[dest].signed
	then
		emit "movl	%eax,	%eax";
		return;
	end

	emit(("mov%sx	%s,	%s"):format(
	     gType[dest].signed and 's' or 'z',
	     gMainRegister[gType[src].size], gMainRegister[gType[dest].size]));
end

local function
toTypeName(signed, size)
	return (signed and 's' or 'u') .. (size * 8);
end

pFactor = function(symtab)
	if gLook.type == "integer"
	then
		emit(("movq	$%d,	%%rax"):format(match("integer").value));
		return "val";
	elseif gLook.type == "signed-integer"
	then
		emit(("movq	$%d, 	%%rax"):format(
		     match("signed-integer").value));
		return "sal";
	elseif gLook.type == "$"
	then
		match '$';
		local id = match("id").id;
		local sym = checkSym(symtab, id);
		emit(("%s	%s,	%%rax"):format(
		     sym.type == "function" and gConf.pie and "movq" or "leaq",
		     getSymAddress(id, sym)));
		return "ptr";
	elseif gLook.type == "id"
	then
		local id	= match("id").id;
		local sym	= checkSym(symtab, id);
		if sym.type == "function"
		then
			pFuncCall(id, symtab);
			return sym.retType;
		else
			emit(("mov	%s,	%s"):format(
			     getSymAddress(id, sym),
			     gMainRegister[gType[sym.type].size]));
			return symtab[id].type;
		end
		return symtab[id].type;
	elseif gLook.type == "type"
	then
		local t = match("type").info;
		local ts, scale = doAddressing(symtab, t);
		emit(("mov	(%%rbx%s), %s"):format(
		     scale, gMainRegister[ts]));
		return t;
	elseif gLook.type == '('
	then
		match '(';
		local t = pValue(symtab);
		match ')'
		return t;
	elseif gLook.type == '-'
	then
		match '-';
		local t = pFactor(symtab);
		emit "neg	%rax";
		return toTypeName(true, gType[t].size);
	elseif gLook.type == "szo"
	then
		match "szo";
		emit(("movq	$%d,	%%rax"):format(
		      gType[match("type").info].size));
		return "val";
	else
		unexpected();
	end
end

local function
castToWord(src, signed)
	doCast(signed and "sal" or "val", src);
end

local function
asmSign(signed)
	return signed and 'i' or '';
end

local function
genericParse(pOperand, handlers, symtab)
	local t			= pOperand(symtab);
	local size, signed	= gType[t].size, gType[t].signed;
	castToWord(t, signed);

	while handlers[gLook.type]
	do
		local op = gLook.type;
		next();

		emit "pushq	%rax";

		local tt		= pOperand(symtab);
		local tsize, tsigned	= gType[tt].size, gType[tt].signed;
		size 	= math.max(size, tsize);
		signed 	= signed and tsigned;
		castToWord(tt, signed);

		handlers[op](signed, size);

		emit "popq	%rdx";
	end

	return toTypeName(signed, size);
end

pTerm = function(symtab)
	local handlers <const> = {
		['*'] = function(signed, size)
			emit(asmSign(signed) .. "mulq	(%rsp)");
		end,
		['/'] = function(signed, size)
			emit "xchg	%rax,	(%rsp)";
			if signed then
				emit("cqo");
			else
				emit "xorq	%rdx,	%rdx";
			end
			emit(asmSign(signed) .. "divq	(%rsp)");
		end,
		['%'] = function(signed, size)
			emit "xchg	%rax,	(%rsp)";
			if signed then
				emit("cqo");
			else
				emit("xorq	%rdx,	%rdx");
			end
			emit(asmSign(signed) .. "divq	(%rsp)");
			emit "movq	%rdx,	%rax";
		end,
	};
	return genericParse(pFactor, handlers, symtab);
end

pExpr = function(symtab)
	local handlers <const> = {
		['+'] = function(signed, size)
			emit "addq	(%rsp),	%rax";
		end,
		['-'] = function(signed, size)
			emit "subq	(%rsp), %rax";
			emit "negq	%rax";
		end,
	};
	return genericParse(pTerm, handlers, symtab);
end

pShift = function(symtab)
	local handlers <const> = {
		["<<"] = function(signed, size)
			emit "xchgq	%rax,	(%rsp)";
			emit "movb	(%rsp),	%cl";
			emit "shlq	%cl,	%rax";
		end,
		[">>"] = function(signed, size)
			emit "xchgq	%rax,	(%rsp)";
			emit "movb	(%rsp),	%cl";
			emit "shrq	%cl,	%rax";
		end,
	};
	return genericParse(pExpr, handlers, symtab);
end

pRelation = function(symtab)
	local handlers <const> = {
		['<'] = function(signed, size)
			emit "cmpq	%rax,	(%rsp)";
			emit((signed and "setl" or "setb") .. "	%al");
			emit "andq	$1,	%rax";
		end,
		['>'] = function(signed, size)
			emit "cmpq	%rax,	(%rsp)";
			emit((signed and "setg" or "seta") .. "	%al");
			emit "andq	$1,	%rax";
		end,
		["<="] = function(signed, size)
			emit "cmpq	%rax,	(%rsp)";
			emit((signed and "setle" or "setbe") ..  "	%al");
			emit "andq	$1,	%rax";
		end,
		[">="] = function(signed, size)
			emit "cmpq	%rax,	(%rsp)";
			emit((signed and "setge" or "setae") .. "	%al");
			emit "andq	$1,	%rax";
		end,
	};
	return genericParse(pShift, handlers, symtab);
end

pEquality = function(symtab)
	local handlers <const> = {
		["=="] = function(signed, size)
			emit "cmpq	(%rsp),	%rax";
			emit "sete	%al";
			emit "andq	$1,	%rax";
		end,
		["!="] = function(signed, size)
			emit "cmpq	(%rsp),	%rax";
			emit "setne	%al";
			emit "andq	$1,	%rax";
		end,
	};
	return genericParse(pRelation, handlers, symtab);
end

pNot = function(symtab)
	if gLook.type == '!'
	then
		match '!';
		local t = pEquality(symtab);
		emit "notq	%rax";
		return t;
	else
		return pEquality(symtab);
	end
end

pAnd = function(symtab)
	local handlers <const> = {
		['&'] = function(signed, size)
			emit "andq	(%rsp),	%rax";
		end,
	};
	return genericParse(pNot, handlers, symtab);
end

pOr = function(symtab)
	local handlers <const> = {
		['|'] = function(signed, size)
			emit "orq	(%rsp),	%rax";
		end,
	};
	return genericParse(pAnd, handlers, symtab);
end

pValue = function(symtab)
	if gLook.type == '?'
	then
		match '?';
		pValue(symtab);
		local elseLabel, endLabel  = getLocalLabel(), getLocalLabel();
		emit "testq	%rax,	%rax";
		emit("jz	" .. elseLabel);

		match ':';
		local t1 = pValue(symtab);
		emit("jmp	" .. endLabel);

		match ':';
		emitLabel(elseLabel);
		local t2 = pValue(symtab);
		emitLabel(endLabel);
		return toTypeName(gType[t1].signed and gType[t2].signed,
				  math.max(gType[t1].size,
					   gType[t2].size));
	else
		return pOr(symtab);
	end
end

pFuncCall = function(id, symtab)
	local sym = checkSym(symtab, id);

	if sym.type ~= "function"
	then
		report(("Cannot call non-function symbol %s"):format(id));
	end

	match '(';

	local count = 0;
	for i = 1, #sym.argType
	do
		count = count + 1;
		local t = pValue(symtab);
		doCast(sym.argType[i], t);
		emit(("push	%s"):format(
		     gMainRegister[gType[t].size]));
		if gLook.type ~= ','
		then
			break;
		end
		match ',';
	end

	if count ~= #sym.argType
	then
		report("Argument number mismatches.");
	end

	match ')';

	emit("callq	" .. id);
	if sym.argSize ~= 0
	then
		emit(("addq	$%d,	%%rsp"):format(
		     sym.argSize))
	end

	return;
end

local function
pVarDef(symtab, t)
	while gLook.type == "id"
	do
		local id = match("id").id;
		symtab["@totalSize"] = symtab["@totalSize"] + gType[t].size;
		symtab["@thisSize"]  = symtab["@thisSize"] + gType[t].size;
		symtab[id] = {
				type	= t,
				offset	= -symtab["@totalSize"],
			     };
		emit(("subq	$%d,	%%rsp"):format(
		     gType[t].size));

		if gLook.type == '='
		then
			match '=';
			local rt = pValue(symtab);
			doCast(t, rt);
			emit(("mov	%s,	%d(%%rbp)"):format(
			     gMainRegister[gType[t].size],
			     symtab[id].offset));
		end

		if gLook.type ~= ','
		then
			break;
		end
		match ',';
	end
end

pStatement = function(symtab)
	if gLook.type == "ret"
	then
		match "ret";
		if gLook.type ~= ';'
		then
			pValue(symtab);	-- stored in %rax as ABI speicifed
		end
		match ';';
		emit "leaveq";
		emit "retq";
	elseif gLook.type == "id"
	then
		local id = match("id").id;
		if gLook.type == '('
		then
			pFuncCall(id, symtab);
			match ';';
		elseif gLook.type == '='
		then
			match '=';
			local sym = checkSym(symtab, id);
			local type = pValue(symtab);
			doCast(sym.type, type);
			match ';';
			emit(("mov	%s,	%s"):format(
			      gMainRegister[gType[sym.type].size],
			      getSymAddress(id, sym)));
		else
			unexpected();
		end
	elseif gLook.type == "type"
	then
		local t		= match("type").info;
		if gLook.type == '('
		then
			local size, scale = doAddressing(symtab, t, function()
				match '=';
				-- Rightside type
				doCast(t, pValue(symtab));
			end);
			emit(("mov	%s,	(%%rbx%s)"):format(
			     gMainRegister[size], scale));
			match ';';
		elseif gLook.type == "id"
		then
			pVarDef(symtab, t);
			match ';';
		else
			unexpected();
		end
	elseif gLook.type == '{'
	then
		pBlock(symtab);
	elseif gLook.type == "if"
	then
		match "if";
		local nextLabel = getLocalLabel();
		pValue(symtab);
		emit "testq	%rax,	%rax";
		emit("jz	" .. nextLabel);
		pStatement(symtab);
		if gLook.type == "else"
		then
			match "else";
			local endLabel = getLocalLabel();
			emit("jmp	" .. endLabel);
			emitLabel(nextLabel);
			pStatement(symtab);
			emitLabel(endLabel);
		else
			emitLabel(nextLabel);
		end
	elseif gLook.type == "for"
	then
		match "for";

		local condLabel, endLabel = getLocalLabel(), getLocalLabel();
		emitLabel(condLabel);
		pValue(symtab);
		emit "testq	%rax,	%rax";
		emit("jz	" .. endLabel);
		pStatement(symtab);
		emit("jmp	" .. condLabel);
		emitLabel(endLabel);
	else
		unexpected();
	end
end

pBlock = function(outsideScope, totalSize, additional)
	local symtab = deriveSymtab(outsideScope);
	symtab["@totalSize"] = totalSize or outsideScope["@totalSize"];
	symtab["@thisSize"]  = 0;
	for name, info in pairs(additional or {})
	do
		symtab[name] = info;
	end

	match '{';

	while gLook.type == "ret" or gLook.type == "break" or
	      gLook.type == "if" or gLook.type == "for" or
	      gLook.type == "id" or gLook.type == "type" or
	      gLook.type == '{'
	do
		pStatement(symtab);
	end

	match '}';

	if symtab["@thisSize"] > 0
	then
		emit(("addq	$%d,	%%rsp"):format(
		     symtab["@thisSize"]));
	end
end

local function
pFuncHeader(symtab, def)
	local prototype = {
				type	= "function",
				retType	= match("type").info,
				argType	= {},
				static	= true,
				def	= def,
			  };

	local name = match("id").id;
	if def and symtab[name] and symtab[name].def
	then
		report("Duplicated definition of function %s", name);
	end

	match '(';

	-- XXX: Add type checks
	local argNames = {};
	while gLook.type == "type"
	do
		local type = match("type").info;
		local name = match("id").id;
		table.insert(prototype.argType, type);
		table.insert(argNames, name);

		if gLook.type ~= ','
		then
			break;
		end
		next();
	end
	match ')';

	local argSize = 0;
	for i, v in ipairs(prototype.argType)
	do
		argSize = argSize + gType[v].size;
	end
	prototype.argSize = argSize;

	local argSyms = {};
	for i, v in ipairs(prototype.argType)
	do
		argSyms[argNames[i]] = {
					type	= v,
					offset	= argSize + 8,
				       };
		argSize = argSize - gType[v].size;	-- 8bytes for pushed rbp
	end

	symtab[name] = prototype;

	return name, prototype, argSyms;
end


local function
pFuncDef(symtab)
	match "fn";

	local name, sym, argSyms = pFuncHeader(symtab, true);
	sym.def = true;

	emitLabel(name);
	emit "push	%rbp";
	emit "movq	%rsp,	%rbp";
	pBlock(symtab, 0, argSyms);
end

-- XXX: Add type checks
local function
pFuncDec(symtab)
	match "fn";
	pFuncHeader(symtab, false);
end

local function
pVarDec(symtab)
	local t = match("type").info;

	while gLook.type == "id"
	do
		symtab[match("id").id] = {
						static	= true,
						type	= t,
						imported= true,
					 };
		if gLook.type ~= ','
		then
			break;
		end
		match ',';
	end
end

local function
pSvarDef(symtab)
	local t = match("type").info;

	while gLook.type == "id"
	do
		local type = gLook.type;
		symtab[match("id").id] = {
						type	= t,
						static	= true,
					 };
		if gLook.type ~= ','
		then
			break;
		end
		next();
	end
end

local function
pExport(symtab)
	match "export";

	while gLook.type == "id"
	do
		local id	= match("id").id;
		local sym	= symtab[id];

		assert(sym.type == "function" or sym.static);

		emit(".global " .. id);

		if gLook.type ~= ','
		then
			break;
		end
		match ',';
	end
end

local function
pProgram()
	local symtab = {};
	emit ".text";
	while gLook.type ~= "EOF"
	do
		if gLook.type == "fn"
		then
			pFuncDef(symtab);
		elseif gLook.type == "dcl"
		then
			match "dcl";
			if gLook.type == "fn"
			then
				pFuncDec(symtab);
			elseif gLook.type == "type"
			then
				pVarDec(symtab);
			else
				unexpected();
			end
			match ';';
		elseif gLook.type == "type"
		then
			pSvarDef(symtab);
			match ';';
		elseif gLook.type == "export"
		then
			pExport(symtab);
			match ';';
		else
			unexpected();
		end
	end

	emit(".bss");
	for name, info in pairs(symtab)
	do
		if info.static and info.type ~= "function" and
		   not info.imported
		then
			local size = gType[info.type].size;
			emitLabel(name);
			emit((".zero " .. size));
		end
	end
	printSymtab(symtab);
end

--[[
--	Main Program
--]]

local i = 1;
while i <= #arg
do
	if arg[i] == "--debug"
	then
		gConf.debug	= true;
	elseif arg[i] == "-no-pie"
	then	gConf.pie	= false;
	elseif arg[i] == "-o"
	then
		if not arg[i + 1]
		then
			io.stderr:write("Option -o needs an argument\n");
			os.exit(-1);
		end
		gConf.output	= arg[i + 1];
		i = i + 1;
	else
		gConf.input	= arg[i];
	end
	i = i + 1;
end

lexerInit(gConf.input);
codegenInit(gConf.output);
pProgram();
match "EOF";
