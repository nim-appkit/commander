import parseopt2
import strutils
import tables

type
  ValueKind = enum
    NO_VALUE 
    INT_VALUE
    FLOAT_VALUE
    STRING_VALUE
    BOOL_VALUE

  Value = object
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

type Flag = ref object
  longName: string
  shortName: string
  description: string
  kind: ValueKind
  required: bool

type Arg = ref object
  name: string
  description: string
  kind: ValueKind
  required: bool

########
# Cmd. #
########

type Cmd = ref object of RootObj
  name: string
  description: string
  help: string
  flags: seq[Flag]
  args: seq[Arg]
  extraArgs: bool

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

# Flag procs.

proc flag*(c: Cmd, longName: string, shortName, description: string = "", kind: ValueKind = BOOL_VALUE, required: bool): Cmd =
  var f = Flag(
    `longName`: longName, 
    `shortName`: shortName,
    `description`: description,
    `kind`: kind, 
    `required`: required
  )
  c.flags.add(f)
  return c

proc strFlag*(c: Cmd, longName: string, shortName, description: string = "", required: bool): Cmd =
  var f = Flag(
    `longName`: longName, 
    `shortName`: shortName,
    `description`: description,
    `kind`: STRING_VALUE, 
    `required`: required
  )
  c.flags.add(f)
  return c

proc intFlag*(c: Cmd, longName: string, shortName, description: string = "", required: bool): Cmd =
  var f = Flag(
    `longName`: longName, 
    `shortName`: shortName,
    `description`: description,
    `kind`: INT_VALUE, 
    `required`: required
  )
  c.flags.add(f)
  return c

# Arg procs.

proc arg*(c: Cmd, name: string, description: string = "", kind: ValueKind = STRING_VALUE, required: bool = false): Cmd =
  var a = Arg(
    `name`: name,
    `description`: description,
    `kind`: kind,
    `required`: required
  )
  c.args.add(a)
  return c

proc intArg*(c: Cmd, name: string, description: string = "", required: bool = false): Cmd =
  var a = Arg(
    `name`: name,
    `description`: description,
    `kind`: INT_VALUE,
    `required`: required
  )
  c.args.add(a)
  return c

proc floatArg*(c: Cmd, name: string, description: string = "", required: bool = false): Cmd =
  var a = Arg(
    `name`: name,
    `description`: description,
    `kind`: FLOAT_VALUE,
    `required`: required
  )
  c.args.add(a)
  return c

proc newCommand*(name: string, description: string = "", help: string = "", extraArgs: bool = false): Cmd =
  Cmd(
    `name`: name,
    `description`: description,
    `help`: help,
    `extraArgs`: extraArgs,
    flags: newSeq[Flag](),
    args: newSeq[Arg](),
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
    flags: newSeq[Flag](),
    args: newSeq[Arg](),
    subcommands: initTable[string, Cmd]()
  )

#############
# Templates #
#############

template Commander(body: stmt): stmt {.immediate, dirty.} =
  var cmdr = Cmdr(
    name: "",
    description: "",
    help: "",
    extraArgs: false,
    flags: newSeq[Flag](),
    args: newSeq[Arg](),
    subcommands: initTable[string, Cmd]()
  )
  var parentCommand: Cmd = cmdr

  block:
    template name(s: stmt): stmt {.immediate, dirty.} =
      parentCommand.name = s

    template description(s: stmt): stmt {.immediate, dirty.} =
      parentCommand.description = s

    template help(s: stmt): stmt {.immediate, dirty.} =
      parentCommand.help = s


    template extraArgs(e: stmt): stmt {.immediate, dirty.} =
      parentCommand.extraArgs = e

    template flag(flagBody: stmt): stmt {.immediate, dirty.} =
      block:
        var f = Flag(kind: BOOL_VALUE)

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

        flagBody

        if f.longName == "":
          raise newException(Exception, "Must set a longName for flags (command $1)!" % [parentCommand.name])
        parentCommand.flags.add(f)

    template arg(argBody: stmt): stmt {.immediate, dirty.} =
      block:
        var a = Arg(kind: STRING_VALUE)

        template name(s: stmt): stmt {.immediate, dirty.} =
          a.name = s

        template kind(s: stmt): stmt {.immediate, dirty.} =
          a.kind = s

        template required(s: stmt): stmt {.immediate, dirty.} = 
          a.required = s

        template description(s: stmt): stmt {.immediate, dirty.} =
          a.description = s

        argBody

        parentCommand.args.add(a)

    template Command(cmdBody: stmt): stmt {.immediate, dirty.} =
      block:
        var cmd = Cmd(
          name: "",
          description: "",
          help: "",
          extraArgs: false,
          flags: newSeq[Flag](),
          args: newSeq[Arg](),
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

  arg:
    name: "name"
    description: "descr"
    required: true


  extraArgs: true

  Command:
    name: "subc"
    help: "sub help"

    Command:
      name: "subsubc"
      help: "lala"

