# nim-commander

Commander is a command-line library for effortless creation of command line applications in the [Nim language](http://nim-lang.org).

## Features

* Git-style nested subcommands with arbitrary depth.
* DSL for dead-simple definition of commands, flags and arguments.
* Automatically generated help with detailed information about flags, arguments, etc.
* Autocomplete with easy integration. (*under development*).

## Install

Commander is best installed with the [Nimble package manager](https://github.com/nim-lang/nimble).

```bash
nimble install commander
```

You can also just clone the repository:

```bash
git clone https://github.com/theduke/nim-commander.git commander
# Compile with additional search path:
nim -p ~/path/to/commander myprogram.nim
```

## Getting started

This is a minimal example for a pseudo `ls` command listing the the files in the current directory.

```nim
import commander
# IMPORTANT: you need to import tables to access flags and arguments!!
import tables

Commander:
  name: "ls" # This should be name of your executale.
  description: "List files."
  help: """Detailed
      multiline
      help."""

  flag:
    longName: "all" # longName is required.
    shortName: "a" # shortName is optional.
    description: "Show all." # Description is optional, but highly suggested.

  arg:
    name: "path" # Name is required.
    description: "Path to list." # Optional.
    required: true
    extraArgs: false # false is the default! If set to true, all additional 
                     # args are available as 'extraArgs' (openArray[string]).

  handle:
    echo("Listing files in directory: " & args["path"].strVal)
    if flags["all"].boolVal:
      echo("Listing all files")

cmdr.run()
```

That's it.
You can now compile and use the program:

```bash
# Print help:
ls help 
ls -h
ls --help

# Run:
ls # => Error: Missing required argument "path"
ls /my/path => Prints "Listing files in directory /my/path"
ls -a /my/path => Prints "Listing..." + "Listing all files"
```

Check out the next example for a more complex setup with nested sub commands, 
different argument types, etc.


## Todo example

This example showcases all features of Commander.
It pseudo-implements a todo app that allows you to list todos, add and delete them.

```nim
import commander
# IMPORTANT: you need to import tables to access flags and arguments!!
import tables

Commander:
  name: "todoist"
  description: "todo manager"
  help: """This is todo manager.
    You can create todos,
    list them,
    and delete them."""

  handle:
    # The main command just prints out the help.
    echo(cmdr.buildHelp())

  flag:
    longName: "verbose" # longName is required. (--verbose)
    shortName: "v" # shortName is optional. (-v)
    kind: BOOL_VALUE # bool flags do not have a value, but just toggle between 
                     # true (supplied) and false (not supplied).
                     # BOOL_VALUE is the default.
    description: "Show detailed output" # Description is optional.
    help: """Multiline
      option
      help."""
    global: true # A global flag will be available to all subcommands!

  Command:
    name: "ls"
    description: "List your todos"

    flag:
      longName: "tag"
      shortName: "t"
      description: "Limit result to the specified tags"
      kind: STRING_VALUE
      multi: true # Multi flags can be supplied multiple times and are available as an array.
                  # eg: flags["myflag"].values[0].strVal

    handle:
      echo("Listing todos...")
      # Access a global flag.
      if flags["verbose"].boolVal:
        echo("Showing detailed list!")
      # Iterate over a multi flag.
      for val in flags["tag"].values:
        echo("Limiting result to tag " & val.strVal)

  Command:
    name: "add"
    description: "Add a new todo"
    
    flag:
      longName: "priority"
      kind: INT_VALUE # Flag value will be converted to int. (access: flags["f"].intVal)
                      # Error when not a valid number!
      default: 5 # Provide a default value.

    flag:
      longName: "category"
      shortName: "c"
      kind: STRING_VALUE
      required: true # Mark flag as required. Will produce error when missing.

    arg:
      name: "todo"
      description: "The todo text."
      required: true # true is the default!

    handle:
      echo("Creating todo")
      # Will have the default value of 5 when not specified.
      var priority = flags["priority"].intVal
      echo("Priority: ", priority.`$`)
      echo("Todo text: " & args["todo"].strVal)

  Command:
    name: "del"
    description: "Delete todo by id"
    extraArgs: true # Allow additional arguments!

    arg:
      name: "id"
      kind: INT_VALUE

    handle:
      echo("Deleting todo with id " & args["id"].intVal.`$`)

      for str in extraArgs:
        echo("Additional argument: ", str)

cmdr.run()
```


## Documentation

### Commander

### Command

### flag

### argument

### Extending a Commander

If you have an existing commander instance, and you want to add additional 
commands to it, you can use the 'extend' template:

```nim
cmdr.extend:
  Command:
    name: "xx"
    ...
```

### Usage without the DSL

If you prefer to not use the DSL style configuration, you can also build your 
commander manually:

```nim
import commander
# IMPORTANT: you need to import tables to access flags and arguments!!
import tables

# Build the commander.
var handlerProc = proc(args, flags: Table[string, Value], extraArgs: openArray[string]) =
  echo("Handling!")

var cmdr = newCommander(
  name="mycmd", 
  description="XX", 
  help="", 
  extraArgs=true, 
  handler=handlerProc
)

# Add a flag.
discard cmdr.flag(
  longName="my-option",
  shortName="",
  description="",
  help="",
  kind=STRING_VALUE,
  required=false,
  multi=false,
  global=false,
  default=newValue("xxx")
)

# Build a subCommand.
var subCmdHandler = proc(args, flags: Table[string, Value], extraArgs: openArray[string]) =
  echo("subcmd")
var subCmd = newCommand(name="cmd", description="Description", help="", extraArgs=false, handler=subCmdHandler)
discard cmdr.addCmd(subCmd)

# Add an argument.
discard subCmd.arg(
  name="subcommand",
  description="",
  help="",
  kind=INT_VALUE,
  required=false,
  default=newValue(45)
)

# Calling build() adds the help command and -h/--help flags.
cmdr.build()

# Run.
cmdr.run()
```

## Additional information

### Changelog

[Changelog](https://github.com/theduke/nim-commander/blob/master/CHANGELOG.md)

### TODO

- [ ] Finish writing documentation.
- [ ] Extendable autocomplete support.
- [ ] Write tests. 
- [ ] Publish nimble package.

### Versioning

This project follows [SemVer](http://semver.org).

### License.

This project is under the [MIT license](https://opensource.org/licenses/MIT).
