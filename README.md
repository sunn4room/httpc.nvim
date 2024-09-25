# httpc.nvim

This neovim plugin just do one thing: send http request under cursor and return the http response to you.

```lua
-- lazy.nvim spec
return {
  "sunn4room/httpc.nvim",
  ft = "http",
  opts = {
    animation = {
      spinner = { "|", "/", "-", "\\" },
      interval = 100,
    },
    magics = {
      -- uuid = function(args) ... end,
      -- encode = function(args) ... end,
      -- decode = function(args) ... end,
      -- ...
      -- builtin magics: processEnv, datetime, randomInt, timestamp, urlencode
      -- usage: {{$<magic> <arg1> <arg2> <args3>}}
    },
  },
}
```

## features

- [x] Spinner to indicate that request is running.
- [x] variable replacement.
  - [x] Define variable inside http file.
  - [x] Use magic lua function in variable replacement.
  - [ ] Read variable from environment files.
- [ ] Response highlight.

## usage

```lua
-- run request under cursor
require("httpc").run()

-- run request somewhere
require("httpc").run({ buf = 0, row = 0, col = 0 })

-- cancel the running request if any
require("httpc").cancel()
```

## Q&A

### Can I customize the spinner highlight group?

Yes, you can.

```lua
{
  animation = {
    spinner = {
      {
        { ">", "Comment" },
        { ">", "Comment" },
        { ">", "Comment" },
      },
      {
        { ">", "Special" },
        { ">", "Comment" },
        { ">", "Comment" },
      },
      {
        { ">", "Comment" },
        { ">", "Special" },
        { ">", "Comment" },
      },
      {
        { ">", "Comment" },
        { ">", "Comment" },
        { ">", "Special" },
      },
    },
  },
}
```

### Can I use another variable during variable declaration?

Yes, you can.

```
@ORG=httpbin
@HOST={{ORG}}.org

###

GET https://{{HOST}}/get
```

### How to include space character in arguments during magic replacement?

```
GET https://httpbin.org/get
Current-Datetime: {{$datetime %Y-%m-%d\ %H:%M:%S}}
```

### How to edit response in buffer?

After request complete, response is printed in cmdline area. At this point, you can only scroll up and down. If you want to edit response in buffer, you can use `:redir` command.

```lua
-- before run request
vim.cmd [[redir @"]]

-- run request
require("httpc").run()

-- after get response
vim.cmd [[redir END]]

-- create a new buffer
vim.cmd [[enew]]

-- paste the response from unnamed register
vim.cmd [[normal p]]
```
