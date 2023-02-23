--[[
--	rclang stage 1 compiler
--	Date:2023.02.23
--	By MIT License.
--	Copyright (c) 2023 Ziyao.
--]]

local io		= require "io";
local string		= require "string";
local math		= require "math";

local gConf = {
			output = "a.S",
			input = "",
	      };

print("rclang stage 1 compiler");
