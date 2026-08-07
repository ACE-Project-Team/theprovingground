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
    Traps. Most of these cost you a function and say nothing about it, so the
    only reliable way to catch them is to count rendered functions against
    declared ones. The first is the worst.

    1. Do not put a `--` inside the FIRST line of a `---` doc comment. LDoc reads
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

    2. A plain `--` comment on the line DIRECTLY above a doc block gets absorbed
    into it, and the function below is dropped. This bites section separators:

        -- -- Wallet helpers ------
        --- A player's current wallet balance.   -- ECON.GetMoney VANISHES

    A blank line between the separator and the doc block fixes it.

    3. Nothing may sit between a doc block and the function it documents. A
    stray `local FOO = 1` in the gap makes LDoc document the local instead and
    drop the function. Hoist the local above the doc block.

    4. `@module` must be in the file's FIRST doc comment. A module header placed
    after an `include(...)` line is not recognised, and the file's whole page is
    never written. AddCSLuaFile/include go below the header, not above it.

    5. Every file with any doc comment needs its own `@module`. LDoc treats each
    file as a module, so an entity's `shared.lua` header does NOT cover its
    `init.lua`; each realm file declares its own (`tpg.ent.flag.server` etc).
    A file that misses this aborts the ENTIRE build with "module(...) name
    deduction failed" and doc/modules is never written.

    6. A doc block above an anonymous `hook.Add`/`net.Receive` callback crashes
    the build outright ("definition cannot be parsed", then an internal LDoc
    error). Give the block an explicit `@function <SomeName>` tag -- use the
    hook's identifier string, which is what you would search for anyway.

    7. An `@{...}` link that does not resolve is only a warning, but it drops
    the function containing it. Link to documented functions only; for locals,
    tables and cross-realm names use `backticks` instead.
]]

-- ARCHITECTURE.md is the way in for someone who has never opened this repo.
-- It is a real file at the root rather than a page that only exists once the
-- docs are generated, because most people will read it on GitHub.
topics = { 'ARCHITECTURE.md', 'README.md' }
