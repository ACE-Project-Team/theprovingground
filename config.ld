--[[
    LDoc configuration for The Proving Ground.

    Build with:  ldoc .

    Output lands in doc/, which is not tracked -- the source is the record, the
    HTML is a convenience. Every module here is a plain table hung off the
    global TPG, not a Lua module you require, so each file declares itself with
    @module and LDoc reads the table functions off it.

    The @realm tag is ours. Garry's Mod runs the same codebase in two places
    and which one a function exists in is the first thing anyone needs to know
    about it -- a client calling something server-only just gets a nil index
    error with no hint as to why.
]]

project     = 'The Proving Ground'
title       = 'The Proving Ground -- gamemode reference'
description = 'A team-based combined-arms gamemode for Garry\'s Mod, built on ACE.'

--[[
    addons/tpg_e2sf_sandbox is deliberately not in here. Its Starfall library
    is already annotated in Starfall's own format (@name, @class library,
    @libtbl), which Starfall's documentation generator reads -- rewriting it in
    LDoc's tags to get it into this build would break the docs that chip
    authors actually read.
]]
file = {
    'gamemode',
    'entities',
}

-- No `style`/`template` here on purpose: leaving them unset makes LDoc use the
-- stylesheet and templates it ships with. Setting `style = true` means "look
-- next to this config file", which only works if you also vendor an ldoc.css.
dir  = 'doc'
sort = false

-- Doc comments are written as markdown -- `backticks` around identifiers and
-- filenames, mostly. LDoc ships its own markdown.lua, so this needs nothing
-- installed beyond LDoc itself.
format = 'markdown'

-- Tables of functions, not classes; showing the arg list without a leading
-- space reads closer to the call you would actually write.
no_space_before_args = true

custom_tags = {
    { 'realm', title = 'Realm' },
}

--[[
    One trap, because it costs you a function and says nothing about it.

    Do not put a `--` inside the FIRST line of a `---` doc comment. LDoc reads
    it as the start of a fresh, undocumented comment, quietly detaches the whole
    block from the function below it, and drops that function from the output
    with no warning and a zero exit code. This was caught by counting the
    rendered functions against the declared ones, which is the only way it
    shows up.

        --- Top N by rating -- not just who is connected.   -- function VANISHES
        --- Top N by rating, not just who is connected.     -- fine

    Continuation lines are fine, and so is the long-bracket block form even in
    its summary. Only the first line of the `---` form is affected. If a
    function you documented is missing from doc/, look here first.
]]

-- ARCHITECTURE.md is the way in for someone who has never opened this repo.
-- It is a real file at the root rather than a page that only exists once the
-- docs are generated, because most people will read it on GitHub.
topics = { 'ARCHITECTURE.md', 'README.md' }
