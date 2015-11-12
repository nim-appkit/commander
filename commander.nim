import parseopt2
import strutils
import tables
import macros

type
  ValueKind = enum
    NO_VALUE 
    INT_VALUE
    FLOAT_VALUE
    STRING_VALUE
    BOOL_VALUE

  Value = ref object
    case kind: ValueKind
    of INT_VALUE:
      intVal: BiggestInt
    of FLOAT_VALUE:
      floatVal: BiggestFloat
    of STRING_VALUE:
      strVal: string
    of BOOL_VALUE:
      boolVal: bool
    of NO_VALUE:
      discard

proc newValue(v: int): Value =
  Value(kind: INT_VALUE, intVal: BiggestInt(v))

proc newValue(v: float): Value =
  Value(kind: FLOAT_VALUE, floatVal: BiggestFloat(v))

proc newValue(v: bool): Value =
  Value(kind: BOOL_VALUE, boolVal: v)

proc newValue(v: string): Value =
  Value(kind: STRING_VALUE, strVal: v)

type Flag = ref object
  longName: string
  shortName: string
  description: string
  kind: ValueKind
  required: bool
  default: Value

type Arg = ref object
  name: string
  description: string
  kind: ValueKind
  required: bool
  default: Value

###########
# CmdData #
###########

type CmdData = ref object of RootObj
  flags: Table[string, Value]
  args: Table[string, Value]
  extraArgs: seq[string]

########
# Cmd. #
########

type Cmd = ref object of RootObj
  name: string
  description: string
  help: string
  flags: Table[string, Flag]
  args: Table[string, Arg]
  extraArgs: bool
  handler: proc(data: CmdData)
  subcommands: Table[string, Cmd]

# Setters.
# 
proc name*(c: Cmd, name: string): Cmd =
  c.name = name

proc description*(c: Cmd, description: string): Cmd =
  c.description = description
  return c

proc help*(c: Cmd, help: string): Cmd =
  c.help = help
  return c

proc extraArgs*(c: Cmd, allow: bool): Cmd =
  c.extraArgs = allow
  return c

proc addCmd(c: Cmd, subc: Cmd): Cmd =
  c.subcommands[subc.name] = subc
  return c

proc handler(c: Cmd, handler: proc(data: CmdData)) =
  c.handler = handler

# Flag procs.

proc flag*(c: Cmd, longName: string, shortName, description: string = "", kind: ValueKind = BOOL_VALUE, required: bool, default: Value = nil): Cmd =
  var f = Flag(
    `longName`: longName, 
    `shortName`: shortName,
    `description`: description,
    `kind`: kind, 
    `required`: required,
    `default`: default
  )
  c.flags[f.longName] = f
  return c

proc strFlag*(c: Cmd, longName: string, shortName, description: string = "", required: bool, default: string = "nodefault"): Cmd =
  var defVal: Value = nil
  if default != "nodefault":
    defVal = newValue(default)
  return c.flag(longName, shortName, description, STRING_VALUE, required, defVal)

proc intFlag*(c: Cmd, longName: string, shortName, description: string = "", required: bool, default: int = -1111): Cmd =
  var defVal: Value = nil
  if default != -1111:
    defVal = newValue(default)
  return c.flag(longName, shortName, description, INT_VALUE, required, defVal)

# Arg procs.

proc arg*(c: Cmd, name: string, description: string = "", kind: ValueKind = STRING_VALUE, required: bool = false, default: Value): Cmd =
  var a = Arg(
    `name`: name,
    `description`: description,
    `kind`: kind,
    `required`: required,
    `default`: default
  )
  c.args[a.name] = a
  return c

proc intArg*(c: Cmd, name: string, description: string = "", required: bool = false, default: int = -1111): Cmd =
  var defVal: Value = nil
  if default != -1111:
    defVal = newValue(default)
  return c.arg(name, description, INT_VALUE, required, defVal)

proc floatArg*(c: Cmd, name: string, description: string = "", required: bool = false, default: float = -1111): Cmd =
  var defVal: Value = nil
  if default != -1111:
    defVal = newValue(default)
  return c.arg(name, description, FLOAT_VALUE, required, defVal)

proc newCommand*(name: string, description: string = "", help: string = "", extraArgs: bool = false): Cmd =
  Cmd(
    `name`: name,
    `description`: description,
    `help`: help,
    `extraArgs`: extraArgs,
    flags: initTable[string, Flag](),
    args: initTable[string, Arg](),
    subcommands: initTable[string, Cmd]()
  )

########
# Cmdr #
########

type Cmdr = ref object of Cmd
  discard

proc newCommander*(name: string, description: string = "", help: string = "", extraArgs: bool = false): Cmdr =
  Cmdr(
    `name`: name,
    `description`: description,
    `help`: help,
    `extraArgs`: extraArgs,
    flags: initTable[string, Flag](),
    args: initTable[string, Arg](),
    subcommands: initTable[string, Cmd]()
  )

#############
# Templates #
#############

template Commander*(body: stmt): stmt {.immediate, dirty.} =
  var cmdr = Cmdr(
    name: "",
    description: "",
    help: "",
    extraArgs: false,
    flags: initTable[string, Flag](),
    args: initTable[string, Arg](),
    subcommands: initTable[string, Cmd]()
  )

  cmdr.extend:
    body

template handlerSetup(cmd: Cmd): stmt {.immediate.} =
  result = newNimNode(nnkStmtList)

  #var cmd = getPointer(cmdVal)

  for name, flag in cmd.flags:
    let def = "var $1 = data[\"$1\"]" % [name]
    let s = parseStmt(def)
    result.add(s)
  for name, arg in cmd.args:
    let def = "var $1 = data[\"$1\"]" % [name]
    let s = parseStmt(def)
    result.add(s)

  echo(repr(result))

  return result

template extend*(cmdr: Cmdr, body: stmt): stmt {.immediate, dirty.} =
  block:
    var parentCommand: Cmd = cmdr
    template name(s: stmt): stmt {.immediate, dirty.} =
      parentCommand.name = s

    template description(s: stmt): stmt {.immediate, dirty.} =
      parentCommand.description = s

    template help(s: stmt): stmt {.immediate, dirty.} =
      parentCommand.help = s


    template extraArgs(e: stmt): stmt {.immediate, dirty.} =
      parentCommand.extraArgs = e

    template handle(handlerBody: stmt): stmt =
      block:
        parentCommand.handler = proc(data: CmdData) =
          handlerSetup(cmd)
          handlerBody

    template flag(flagBody: stmt): stmt {.immediate, dirty.} =
      block:
        var f = Flag(kind: BOOL_VALUE, longName: "")

        template longName(s: stmt): stmt {.immediate, dirty.} =
          f.longName = s

        template shortName(s: stmt): stmt {.immediate, dirty.} =
          f.shortName = s

        template kind(s: stmt): stmt {.immediate, dirty.} =
          f.kind = s

        template required(s: stmt): stmt {.immediate, dirty.} = 
          f.required = s

        template description(s: stmt): stmt {.immediate, dirty.} =
          f.description = s

        template default(s: stmt): stmt {.immediate, dirty.} =
          block:
            var val = newValue(s)
            if val.kind != f.kind:
              raise newException(Exception, "Invalid type for for default value of flag $1: got $2 instead of $3" % [f.longName, val.kind.`$`, f.kind.`$`])

            f.default = val

        flagBody

        if f.longName == "":
          raise newException(Exception, "Must set a longName for flags (command $1)!" % [parentCommand.name])
        if parentCommand.flags.contains(f.longName):
          raise newException(Exception, "Duplicate flag longName '$1' for command $2" % [f.longName, parentCommand.name])
        if parentCommand.args.contains(f.longName):
          raise newException(Exception, "Cant specify a flag with a longName that exists as argument (command $1, flag $2)" % [parentCommand.name, f.longName])

        parentCommand.flags[f.longName] = f

    template arg(argBody: stmt): stmt {.immediate, dirty.} =
      block:
        var a = Arg(kind: STRING_VALUE, name: "")

        template name(s: stmt): stmt {.immediate, dirty.} =
          a.name = s

        template kind(s: stmt): stmt {.immediate, dirty.} =
          a.kind = s

        template required(s: stmt): stmt {.immediate, dirty.} = 
          a.required = s

        template description(s: stmt): stmt {.immediate, dirty.} =
          a.description = s

        template default(s: stmt): stmt {.immediate, dirty.} =
          block:
            var val = newValue(s)
            if val.kind != a.kind:
              raise newException(Exception, "Invalid type for for default value of argument $1: got $2 instead of $3" % [a.name, val.kind.`$`, a.kind.`$`])
            f.default = val

        argBody

        if a.name == "":
          raise newException(Exception, "Must set a name for arguments (command $1)!" % [parentCommand.name])
        if parentCommand.args.contains(a.name):
          raise newException(Exception, "Duplicate argument name '$1' for command $2" % [a.name, parentCommand.name])
        if parentCommand.flags.contains(a.name):
          raise newException(Exception, "Cant specify an argument with a name that exists as argument longName (command $1, arg $2)" % [parentCommand.name, a.name])

        parentCommand.args[a.name] = a

    template Command(cmdBody: stmt): stmt {.immediate, dirty.} =
      block:
        var cmd = Cmd(
          name: "",
          description: "",
          help: "",
          extraArgs: false,
          flags: initTable[string, Flag](),
          args: initTable[string, Arg](),
          subcommands: initTable[string, Cmd]()
        )
        var oldParent = parentCommand
        var parentCommand = cmd

        cmdBody

        if cmd.name == "":
          raise newException(Exception, "Must specify name for commands")
        discard oldParent.addCmd(cmd)

    body

Commander:
  name: "main"
  description: """
  long description
  """

  help: """
  the help text
  """

  flag:
    longName: "lala"
    shortName: "l"
    required: true
    description: "flag description"
    kind: STRING_VALUE
    default: "default"

  arg:
    name: "name"
    description: "descr"
    required: true


  handle:
    echo(lala)

  extraArgs: true

  Command:
    name: "subc"
    help: "sub help"

    Command:
      name: "subsubc"
      help: "lala"

