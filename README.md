> [!NOTE]
> please read [this link](https://learn.microsoft.com/en-us/aspnet/core/test/http-files).

# httpc.nvim

This neovim plugin just do one thing: send http request under cursor and return the http response to you.

```lua
-- lazy.nvim spec
return {
  "sunn4room/httpc.nvim",
  ft = "http",
  opts = {
    register = "_", -- the register used to hold the response
    animation = {
      spinner = { "|", "/", "-", "\\" },
      interval = 100,
    },
    magics = {
      -- processEnv = function(args) ... end,
      -- datetime = function(args) ... end,
      -- randomInt = function(args) ... end,
      -- timestamp = function(args) ... end,
      -- urlencode = function(args) ... end,
      -- ...
      -- usage: {{$<magic> <arg1> <arg2> <args3>}}
    },
    patterns = {
      -- json = "^application/.*json.*$",
      -- ...
      -- get lang from content-type for highlights.
    },
  },
}
```

> [!NOTE]
> neovim doesn't recogize `http` ft by default.
>
> ```lua
> vim.filetype.add {
>   extension = {
>     http = "http",
>     rest = "http",
>   },
> }
> ```

## features

- [x] Request parse.
  - [x] method
  - [x] url
  - [x] http version
  - [x] headers
  - [x] body
  - [x] external body
  - [x] form
  - [x] graphql
- [x] Spinner to indicate that request is running.
- [x] variable replacement.
  - [x] Define variable inside http file.
  - [x] Use magic lua function in variable replacement.
  - [x] Read variable from environment files.
- [x] Response highlight.

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

### How to special the env during reading variables from env files?

By default, httpc.nvim read variables from `http-client.env.json` and `http-client.env.json.user` with `dev` env.

```lua
vim.b.http_client_env = "prod"
```
