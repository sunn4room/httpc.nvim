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
      -- builtin magics: processEnv, date, randomInt, timestamp, urlencode
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
Current-Datetime: {{$date %Y-%m-%d\ %H:%M:%S}}
```
