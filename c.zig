pub usingnamespace @cImport({
    @cDefine("_XOPEN_SOURCE", "700");
    @cInclude("locale.h");
    @cInclude("notcurses/notcurses.h");
});
