# rclang

rclang (rc stands for Retro Cpu) is a programming language designed for retro
CPUs, exactly 8bit CPUs such as Z80.

## Development

- Stage 1: Compiler written in Lua, producing x86-64 code. We check our
  prototype and do syntax designing
- Stage 2: Compiler written in Lua with various code generators and
  optimization via [lxcf](https://github.com/ziyao233/lxcf)
- Stage 3: Compiler written in rclang itself and running on retro systems

## License

By MIT License. Copyright (c) 2023 Ziyao.
