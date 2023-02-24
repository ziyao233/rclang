--[[
--	rclang stage 1 compiler
--	Date:2023.02.24
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
local gTypeList <const> = {"ptr","val","sal","u8","s8","u16","s16",
			   "u32","s32","u64","s64"};
local gType = {};
for _,type in pairs(gTypeList)
do
	gType[type] = true;
end
local function next()
	gPos = gSource:match("()%S",gPos);
	if not gPos
	then
		gLook = nil;
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
		sNum,gPos = gSource:match(n == 'x' and "(0x[%dabcdef]+)()" or
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
					name	= id,
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

local function match(type)
	if gLook.type ~= type
	then
		error(("Expected %s, got %s"):format(type,gLook.type));
	end
	next();
end

local function lexerInit(path)
	gSource = assert(io.open(path)):read("a");
	gLook,gIndex = "",1;
	next();
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
while gLook
do
	print(gLook.type,gLook.id or gLook.name or gLook.value or "");
	next();
end
