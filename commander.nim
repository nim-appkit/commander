import parseopt2
import strutils
import tables
import macros
import sequtils
from terminal import nil

proc trim(s: string): string =
  var n: string

  # Trim left.
  for i, c in s:
    if c in Whitespace or c in NewLines:
      continue
    n = s[i..s.len()]
    break
  
  # Trim right.
  var i = n.len() -1
  while i >= 0:
    if n[i] in Whitespace or n[i] in NewLines:
      i -= 1
      continue
    n = n[0..i]
    break

  return n

type ValidationError = object of Exception
  discard

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

proc newValue(v: BiggestInt): Value =
  Value(kind: INT_VALUE, intVal: v)

proc newValue(v: float): Value =
  Value(kind: FLOAT_VALUE, floatVal: BiggestFloat(v))

proc newValue(v: bool): Value =
  Value(kind: BOOL_VALUE, boolVal: v)

proc newValue(v: string): Value =
  Value(kind: STRING_VALUE, strVal: v)

proc newValue(kind: ValueKind, arg, name: string): Value =
  case kind
    of INT_VALUE:
      try:
        var i = parseBiggestInt(arg)
        return newValue(i)
      except:
        raise newException(ValidationError, "Argument $2 must be a number." % [name])

    of FLOAT_VALUE:
      try:
        var f = parseFloat(arg)
        return newValue(f)
      except:
        raise newException(ValidationError, "Argument $2 must be a decimal number." % [name])

    of STRING_VALUE:
      return newValue(arg)

    of BOOL_VALUE:
      case arg.toLower()
      of "1", "y", "yes", "true":
        return newValue(true)
      of "0", "n", "no", "false", "":
        return newValue(false)
      else:
        raise newException(
          Exception, 
          "Argument $2 must be a yes/no value. (yes/no, y/n, true/false, 1/0)." % [name]
        )
    of NO_VALUE:
      return Value(kind: NO_VALUE)

type Flag = ref object
  longName: string
  shortName: string
  description: string
  help: string
  kind: ValueKind
  required: bool
  default: Value
  global: bool

type Arg = ref object
  name: string
  description: string
  help: string
  kind: ValueKind
  required: bool
  default: Value

type HandlerFunc = proc(args, flags: Table[string, Value], extraArgs: openArray[string])


########
# Cmd. #
########


type Cmd = ref object of RootObj
  name: string
  description: string
  help: string
  flags: Table[string, Flag]
  args: OrderedTable[string, Arg]
  extraArgs: bool
  handler: HandlerFunc
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

proc handler(c: Cmd, handler: HandlerFunc) =
  c.handler = handler

# Flag procs.

proc newFlag(longName, shortName, description, help: string = "", kind: ValueKind = BOOL_VALUE, required: bool = false, default: Value = nil, global: bool = false): Flag =
  Flag(
    `longName`: longName, 
    `shortName`: shortName,
    `description`: description,
    `help`: help,
    `kind`: kind, 
    `required`: required,
    `default`: default,
    `global`: global
  )

proc flag*(c: Cmd, longName: string, shortName, description, help: string = "", kind: ValueKind = BOOL_VALUE, required: bool, default: Value = nil): Cmd =
  var f = newFlag(longName, shortName, description, help, kind, required, default)
  c.flags[f.longName] = f
  return c

# Arg procs.

proc newArg(name, description, help: string = "", kind: ValueKind = STRING_VALUE, required: bool = false, default: Value = nil): Arg =
  Arg(
    `name`: name,
    `description`: description,
    `help`: help,
    `kind`: kind,
    `required`: required,
    `default`: default
  )

proc arg*(c: Cmd, name: string, description, help: string = "", kind: ValueKind = STRING_VALUE, required: bool = false, default: Value): Cmd =
  var a = newArg(name, description, help, kind, required, default)
  c.args[a.name] = a
  return c

proc flagByShortName(c: Cmd, shortName: string): Flag =
  for flag in c.flags.values:
    if flag.shortName == shortName:
      return flag

  return nil

proc newCommand*(name: string, description, help: string = "", extraArgs: bool = false): Cmd =
  Cmd(
    `name`: name,
    `description`: description,
    `help`: help,
    `extraArgs`: extraArgs,
    flags: initTable[string, Flag](4),
    args: initOrderedTable[string, Arg](4),
    subcommands: initTable[string, Cmd](4)
  )

###########
# CmdData #
###########

type CmdData = ref object of RootObj
  flags: Table[string, Value]
  args: Table[string, Value]
  extraArgs: seq[string]
  cmd: Cmd

########
# Cmdr #
########

type Cmdr = ref object of Cmd
  discard

proc newCommander*(name: string, description, help: string = "", extraArgs: bool = false): Cmdr =
  Cmdr(
    `name`: name,
    `description`: description,
    `help`: help,
    `extraArgs`: extraArgs,
    flags: initTable[string, Flag](4),
    args: initOrderedTable[string, Arg](4),
    subcommands: initTable[string, Cmd](4)
  )

proc writeError(err: string) =
  terminal.styledEcho(terminal.fgRed, "Error: ", terminal.fgWhite, err)

proc buildSubCmdHelp(c: Cmd, indent: int, parentNames: string): string =
  var h = ""
  var pref = " ".repeat(indent)
  for name, cmd in c.subcommands:
    h &= pref & "* " & cmd.name
    if cmd.description != "": h &=": " & cmd.description
    h &= "\n"
    if cmd.subcommands.len() > 0:
      h &=cmd.buildSubCmdHelp(indent + 4, parentNames & c.name & " ")

  return h

proc buildHelp(c: Cmd, parentNames: string, detailed: bool, subCmds: bool): string =
  var name = parentNames & c.name
  var h = "Usage instructions for command: " & name & "\n\n"
  h &= "" & c.name
  if c.description != "":
    h &= ": " & c.description.trim()

  h &= "\n\n"
  h &= "" & name
  for name, flag in c.flags:
    h &= " "
    if not flag.required: h &="[" 
    if flag.shortName != "": h &="-" & flag.shortName & " "
    h &= "--" & flag.longName
    if not flag.required: h &="]"

  for name, arg in c.args:
    h &= " "
    if not arg.required: h &="[" 
    h &=arg.name
    if not arg.required: h &="]" 

  if c.extraArgs:
    h &=" [...]"

  h &= "\n\n"

  if subCmds and c.subcommands.len() > 0:
    h &="## Subcommands:\n\n"

    h &=c.buildSubCmdHelp(4, "")

  if c.flags.len() > 0:
    h &="\n## Flags:\n"

    for name, flag in c.flags:
      h &="\n    * "

      if flag.shortName != "": h &= "-" & flag.shortName & " "
      h &= "--" & flag.longName
      if flag.description != "": h &= ": " & flag.description

      if flag.help != "" and detailed:
        for line in flag.help.trim().splitLines():
          h &= "\n      " & line.trim()

      h &= "\n"

  if c.args.len() > 0:
    h &= "\n## Arguments:\n"

    for name, arg in c.args:
      h &= "\n    * " & arg.name
      if arg.description != "": h &= ": " & arg.description

      if arg.help != "" and detailed:
        for line in arg.help.trim().splitLines():
          h &="\n      " & line.trim()

      h &= "\n"

  if detailed and c.help != "":
    h &= "\n\n"
    for line in c.help.trim().splitLines():
      h &= line.trim() & "\n"

  return h

proc build(c: Cmdr) =
  # Add a help command.

  var helpCmd = newCommand("help", "Show detailed usage information.", extraArgs=true)
  helpCmd.handler = proc(args, flags: Table[string, Value], extraArgs: openArray[string]) =
    var cmd: Cmd = c
    var names = c.name & " "
    if extraArgs.len() > 0:
      for arg in extraArgs:
        if not cmd.subcommands.hasKey(arg):
          writeError("Can't show help for unknown subcommand '" & arg & "'")
          quit(1) 

        names &= arg & " " 
        cmd = cmd.subcommands[arg]

    echo(cmd.buildHelp(names, true, true))

  discard c.addCmd(helpCmd)

proc buildData(c: Cmdr): CmdData  =
  var data = CmdData(
    args: initTable[string, Value](4),
    flags: initTable[string, Value](4),
    extraArgs: newSeq[string]()
  )

  # Read OS arguments with parseopt2.

  let opts = toSeq(getopt())

  var cmd: Cmd = c
  let orderedArgs = toSeq(cmd.args.values)

  var index = 0
  while index < opts.len():
    let row = opts[index]
    let kind = row.kind
    let key = row.key
    let val = row.val

    # Increment index.
    index += 1

    case kind
    of cmdArgument:
      # Handle arguments.

      let arg = trim(key) 
      if cmd.subcommands.contains(arg):
        # Subcommand found.
        cmd = cmd.subcommands[arg]
        continue

      # No subcommand found, so assume a regular argument.
      if data.args.len() < cmd.args.len():
        var argSpec = orderedArgs[data.args.len()]
        # Build argument value.
        # Note: throws exception if values are incompatible.
        data.args[argSpec.name] = newValue(argSpec.kind, arg, argSpec.name)
      else:
        # No more arguments configured.
        if cmd.extraArgs:
          # Extra args allowed, so add the arg.
          data.extraArgs.add(arg)
        else:
          # Invalid extra argument.
          raise newException(ValidationError, "Invalid extra argument '" & arg & "'.")

    of cmdLongOption:
      var name = key
      if not cmd.flags.hasKey(name):
        # Invalid flag.
        raise newException(ValidationError, "Unknown flag: '--" & name & "'.")

      # Valid flag.
      let flagSpec = cmd.flags[name]
      var flagVal = val
      if flagSpec.kind == BOOL_VALUE and val == "":
        flagVal = "yes"

      # Ensure that the value is correct.
      if flagSpec.kind == STRING_VALUE and flagSpec.required and val == "":
        raise newException(
          ValidationError, 
          "Must supply non-empty value for required flag '--" & flagSpec.longName & "'."
        )

      data.flags[name] = newValue(flagSpec.kind, flagVal, name)

    of cmdShortOption:
      var name = key
      var val = ""
      let flagSpec = cmd.flagByShortName(name)
      if flagSpec == nil:
         # Invalid flag.
        raise newException(ValidationError, "Unknown flag: '-" & name & "'.")

      # Valid flag.
      
      # Check if we need a value.
      if flagSpec.kind != BOOL_VALUE:
        # Check if additional arg is supplied.
        # Note: index was already incremented above!!
        if opts.len() < index or opts[index].kind != cmdArgument:
          raise newException(Exception, "Missing value for option '-" & flagSpec.shortName & "'.")

        # Set val to value of next argument.
        val = opts[index].key
        # Increment index to skip short option value.
        index += 1

      # Ensure that the value is correct.
      if flagSpec.kind == STRING_VALUE and flagSpec.required and val == "":
        raise newException(ValidationError, "Must supply non-empty value for required flag '-" & name & "'.")

      data.flags[flagSpec.longName] = newValue(flagSpec.kind, val, name)

    of cmdEnd:  assert(false) # cannot happen 

  # Check that all arguments have been provided.
  for argSpec in cmd.args.values:
    if not data.args.hasKey(argSpec.name):
      # Argument not supplied, check if it is required.
      if argSpec.required:
        # Arg is required, but not provided.
        raise newException(ValidationError, "Missing required argument '" & argSpec.name & "'.")
      else:
        if argSpec.default != nil:
          # Default value supplied, so use it.
          data.args[argSpec.name] = argSpec.default
        else:
          # No default value, so use the zero value.
          var value = Value(kind: argSpec.kind)
          if argSpec.kind == STRING_VALUE:
            # Set empty string to prevent nil pointer problems.
            value.strVal = ""
          data.args[argSpec.name] = value

  # Check flags.
  for spec in cmd.flags.values:
    if not data.flags.hasKey(spec.longName):
      if spec.required:
        raise newException(ValidationError, "Missing required flag '--" & spec.longName & "'.")

      # Flag not required, so set default value.
      if spec.default != nil:
        # Default value supplied, so use it.
        data.flags[spec.longName] = spec.default
      else:
        # No default value, so use the zero value.
        var value = Value(kind: spec.kind)
        if spec.kind == STRING_VALUE:
          # Set empty string to prevent nil pointer problems.
          value.strVal = ""
        data.flags[spec.longName] = value

  data.cmd = cmd
  return data

proc run(c: Cmdr) =
  var data: CmdData
  try:
    data = c.buildData()
  except ValidationError:
    writeError(getCurrentExceptionMsg())
    echo("Use -h, --help or 'help' to show usage information.")
    quit(1)

  data.cmd.handler(data.args, data.flags, data.extraArgs)

#############
# Templates #
#############

template Commander*(body: stmt): stmt {.immediate, dirty.} =
  var cmdr = Cmdr(
    name: "",
    description: "",
    help: "",
    extraArgs: false,
    flags: initTable[string, Flag](4),
    args: initOrderedTable[string, Arg](4),
    subcommands: initTable[string, Cmd](4)
  )

  cmdr.extend:
    body

macro setupHandler(cmd: expr): stmt =
  result = newStmtList()

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

    template handle(handlerBody: stmt): stmt {.immediate, dirty.} =
      block:
        setupHandler(parentCommand)
        parentCommand.handler = proc(args, flags: Table[string, Value], extraArgs: openArray[string]) =
          handlerBody

    template flag(flagBody: stmt): stmt {.immediate, dirty.} =
      block:
        var f = newFlag()

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

        template help(s: stmt): stmt {.immediate, dirty.} =
          f.help = s

        template default(s: stmt): stmt {.immediate, dirty.} =
          block:
            var val = newValue(s)
            if val.kind != f.kind:
              raise newException(ValidationError, "Invalid type for for default value of flag $1: got $2 instead of $3" % [f.longName, val.kind.`$`, f.kind.`$`])

            f.default = val

        flagBody

        if f.longName == "":
          raise newException(ValidationError, "Must set a longName for flags (command $1)!" % [parentCommand.name])
        if parentCommand.flags.contains(f.longName):
          raise newException(ValidationError, "Duplicate flag longName '$1' for command $2" % [f.longName, parentCommand.name])
        if parentCommand.args.contains(f.longName):
          raise newException(ValidationError, "Cant specify a flag with a longName that exists as argument (command $1, flag $2)" % [parentCommand.name, f.longName])

        parentCommand.flags[f.longName] = f

    template arg(argBody: stmt): stmt {.immediate, dirty.} =
      block:
        var a = newArg()

        template name(s: stmt): stmt {.immediate, dirty.} =
          a.name = s

        template kind(s: stmt): stmt {.immediate, dirty.} =
          a.kind = s

        template required(s: stmt): stmt {.immediate, dirty.} = 
          a.required = s

        template description(s: stmt): stmt {.immediate, dirty.} =
          a.description = s

        template help(s: stmt): stmt {.immediate, dirty.} =
          a.help = s

        template default(s: stmt): stmt {.immediate, dirty.} =
          block:
            var val = newValue(s)
            if val.kind != a.kind:
              raise newException(ValidationError, "Invalid type for for default value of argument $1: got $2 instead of $3" % [a.name, val.kind.`$`, a.kind.`$`])
            f.default = val

        argBody

        if a.name == "":
          raise newException(ValidationError, "Must set a name for arguments (command $1)!" % [parentCommand.name])
        if parentCommand.args.contains(a.name):
          raise newException(ValidationError, "Duplicate argument name '$1' for command $2" % [a.name, parentCommand.name])
        if parentCommand.flags.contains(a.name):
          raise newException(ValidationError, "Cant specify an argument with a name that exists as argument longName (command $1, arg $2)" % [parentCommand.name, a.name])

        parentCommand.args[a.name] = a

    template Command(cmdBody: stmt): stmt {.immediate, dirty.} =
      block:
        var cmd = Cmd(
          name: "",
          description: "",
          help: "",
          extraArgs: false,
          flags: initTable[string, Flag](4),
          args: initOrderedTable[string, Arg](4),
          subcommands: initTable[string, Cmd](4)
        )
        var oldParent = parentCommand
        var parentCommand = cmd

        cmdBody

        if cmd.name == "":
          raise newException(Exception, "Must specify name for commands")
        if cmd.handler == nil:
          raise newException(Exception, "Must specify a handler for command " & cmd.name)
        discard oldParent.addCmd(cmd)

    body

    cmdr.build()

Commander:
  name: "main"
  description: """
  long description
  """

  help: """
  long 
  multiline
   help 
   text!
  """

  flag:
    longName: "lala"
    shortName: "l"
    required: true
    description: "flag description"
    kind: STRING_VALUE
    help:
      """Long 
      multiline
      help
      text"""

  flag:
    longName: "flag2"

  arg:
    name: "name"
    description: "descr"
    required: true
    help: """Long
    multin
    help
    text"""

  arg:
    name: "otherarg"

  handle:
    echo(flags["lala"].strVal)

  extraArgs: true

  Command:
    name: "subc"
    help: "sub help"

    handle:
      echo("Subc handler")

    Command:
      name: "subsubc"
      help: "lala"

      handle:
        echo("sub sub c handler")

cmdr.run()