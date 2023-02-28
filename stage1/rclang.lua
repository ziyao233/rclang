--[[
--	rclang stage 1 compiler
--	Date:2023.02.28
--	By MIT License.
--	Copyright (c) 2023 Ziyao.
--]]

local io		= require "io";
local string		= require "string";
local math		= require "math";

local gConf = {
			output = arg[2],
			input = arg[1],
	      };

local function report(msg)
	error(msg);
end

--[[	The lexer	]]
local gSource,gLook,gPos;
local gSingleOpList <const> = {'?',':',',','|','^','&','+','-','*','/','%',
			       '(',')',';','{','}','>','<','!','=','[',']'};
local gSingleOp = {};
for _,c in pairs(gSingleOpList)
do
	gSingleOp[c] = true;
end
local gKeywordList <const> = {"for","fn","if","else","dcl","ret","break"};
local gKeyword = {};
for _,keyword in pairs(gKeywordList)
do
	gKeyword[keyword] = true;
end
local gType = {"ptr","val","sal","u8","s8","u16","s16",
			   "u32","s32","u64","s64"};
local gType <const> = 
	{
		ptr	= { size = 64,	signed = false	},
		val	= { size = 64,	signed = false	},
		sal	= { size = 64,	signed = true	},
		u8	= { size = 8,	signed = false	},
		s8	= { size = 8,	signed = true	},
		u16	= { size = 16,	signed = false	},
		s16	= { size = 16,	signed = true	},
		u32	= { size = 32,	signed = false	},
		s32	= { size = 32,	signed = true	},
		u64	= { size = 64,	signed = false	},
		s64	= { size = 64,	signed = true	},
	};
local function next()
	gPos = gSource:match("()%S",gPos);
	if not gPos
	then
		gLook = { type = "EOF" };
		return;
	end
	local c,n = gSource:sub(gPos,gPos),gSource:sub(gPos + 1,gPos + 1);

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
		gLook =  {
				type	= "number",
				value	= tonumber(sNum),
			 };
	elseif c:match("[%a_]")
	then
		local id;
		id,gPos = gSource:match("([%a_]+)()",gPos);

		if gType[id]
		then
			gLook = {
					type	= "type",
					info	= gType[id],
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
		error(("Unrecognised character %s"):format(c));
	end
	return gLook;
end

local function match(type,msg)
	if gLook.type ~= type
	then
		error(("Expected %s, got %s"):format(msg or type,gLook.type));
	end
	local tok = gLook;
	next();
	return tok;
end

local function lexerInit(path)
	gSource = assert(io.open(path)):read("a");
	gLook,gIndex = "",1;
	next();
end

local gOutputFile;
local function codegenInit(path)
	gOutputFile = path and assert(io.open(path,"w")) or io.stdout;
end

local function emit(s)
	gOutputFile:write("\t" .. s .. "\n");
end

local function printSymtab(symtab)
	io.stderr:write("\n====Symbol Table====\n");
	for name,sym in pairs(symtab)
	do
		io.stderr:write(("%s:\ttype=%s\n"):format(name,sym.type));
	end
end

local pFuncDec;

pFuncDec = function(symtab)
	match("dcl");
	match("fn");

	local prototype = {
				type	= "function",
				retType	= match("type").info,
				argType = {},
			  };
	local name = match("id").id;
	match('(');
	while gLook.type == "type"
	do
		table.insert(prototype.argType,match("type").info);
		if gLook.type ~= ','
		then
			break;
		end
		next();
	end
	match(')');
	symtab[name] = prototype;
end

local function pProgram()
	local symtab = {};
	while gLook.type ~= "EOF"
	do
		pFuncDec(symtab);
		match(';');
	end
	printSymtab(symtab);
end

--[[
--	Main Program
--]]

if not gConf.input
then
	io.stderr:write("No source specified\n");
	os.exit(-1);
end

lexerInit(gConf.input);
pProgram();
match("EOF");
