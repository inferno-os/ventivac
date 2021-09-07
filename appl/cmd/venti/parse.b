implement Ventiparse;

include "sys.m";
include "draw.m";
include "string.m";
include "arg.m";
include "venti.m";
include "vac.m";

sys: Sys;
str: String;
venti: Venti;
vac: Vac;

fprint, sprint, print, fildes: import sys;
Score, Scoresize, Pointervarmask, Root, Entry, Entrysize, Entrydir, Dirtype, Datatype, Pointertype0: import venti;
Direntry, Metablock, Metaentry, Metablocksize, Metaentrysize: import vac;

Ventiparse: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;

	venti->init();
	vac->init();

	arg->init(args);
	arg->setusage(arg->progname() + " [type]");
	while((c := arg->opt()) != 0)
		case c {
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args > 1)
		arg->usage();

	d := read();

	dtype := "";
	if(len args == 1)
		dtype = hd args;
	if(dtype == nil)
		dtype = guesstype(d);
	if(dtype == nil)
		error("could not guess type");

	case str->tolower(dtype) {
	"vac" or "root" =>
		root(d);
	"entry" =>
		entry(d);
	"entries" =>
		entries(d);
	"direntry" =>
		direntry(d);
	"metablock" =>
		metablock(d);
	"dir" or "metablocks" =>
		metablocks(d);
	"pointers" =>
		pointers(d);
	"rpointers" =>
		rpointers(d);
	* =>
		fprint(fildes(2), "bad type: %s\n", hd args);
		arg->usage();
	}
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
}

zeros(d: array of byte): int
{
	n := 0;
	for(i := 0; i < len d; i++)
		if(d[i] == byte 0)
			n++;
	return n;
}

guesstype(d: array of byte): string
{
	if(len d < 4)
		return nil;
	v := g32(d, 0);
	if(v == Vac->Direntrymagic)
		return "direntry";
	if(v == Vac->Metablockmagic)
		return "metablocks";
	if(len d == 300)
		return "root";

	nz := zeros(d);
	if(len d % Entrysize == 0 && nz > (8*len d/Entrysize))
		return "entries";
	if(len d % Scoresize == 0 && len d % (Scoresize+8) == 0) {
		if(nz > 2*len d/Scoresize)
			return "rpointers";
		return "pointers";
	}
	if(len d % Scoresize == 0)
		return "pointers";
	if(len d % (Scoresize+8) == 0)
		return "rpointers";
	return nil;
}

read(): array of byte
{
	d := array[0] of byte;
	buf := array[8*1024] of byte;
	for(;;) {
		n := sys->read(sys->fildes(0), buf, len buf);
		if(n == 0)
			break;
		if(n < 0)
			error(sprint("reading data: %r"));
		newd := array[len d+n] of byte;
		newd[:] = d;
		newd[len d:] = buf[:n];
		d = newd;
	}
	return d;
}

root(d: array of byte)
{
	r := Root.unpack(d);
	if(r == nil)
		error(sprint("unpacking root: %r"));
	printroot(r);
}

printroot(r: ref Root)
{
	print("Root:\n");
	print("\tversion=%d\n", r.version);
	print("\tname=%s\n", r.name);
	print("\trtype=%s\n", r.rtype);
	print("\tscore=%s\n", r.score.text());
	print("\tblocksize=%d\n", r.blocksize);
	print("\tprev=%s\n", (*r.prev).text());
	print("venti/read %d %s | venti/parse entries\n", Dirtype, r.score.text());
}

entry(d: array of byte)
{
	e := Entry.unpack(d);
	if(e == nil)
		error(sprint("unpacking entry: %r"));
	printentry(e);
}

entries(d: array of byte)
{
	if(len d % Entrysize != 0)
		error(sprint("data (%d bytes) not multiple of Entrysize (%d bytes)", len d, Entrysize));
	for(i := 0; i+Entrysize <= len d; i += Entrysize)
		entry(d[i:i+Entrysize]);
}

printentry(e: ref Entry)
{
	print("Entry:\n");
	print("\tgen=%d\n", e.gen);
	print("\tpsize=%d\n", e.psize);
	print("\tdsize=%d\n", e.dsize);
	print("\tflags=%d\n", e.flags);
	print("\tdepth=%d\n", e.depth);
	print("\tsize=%bd\n", e.size);
	print("\tscore=%s\n", e.score.text());
	if(e.depth > 0) {
		which := "pointers";
		dtype := Pointertype0+e.depth-1;
		if(e.flags & Venti->Entryvarblocks) {
			which = "rpointers";
			dtype |= Pointervarmask;
		}
		print("venti/read %d %s | venti/parse %s\n", dtype, e.score.text(), which);
	} else {
		dtype := Datatype;
		pipe := "";
		if(e.flags & Entrydir) {
			dtype = Dirtype;
			pipe = " | venti/parse entries";
		}
		print("venti/read %d %s%s\n", dtype, e.score.text(), pipe);
	}
}

direntry(d: array of byte)
{
	de := Direntry.unpack(d);
	if(de == nil)
		error(sprint("unpacking direntry: %r"));
	printdirentry(de);
}

printdirentry(de: ref Direntry)
{
	print("Direntry:\n");
	print("\tversion=%d\n", de.version);
	print("\telem=%s\n", de.elem);
	print("\tentry=%d\n", de.entry);
	print("\tgen=%d\n", de.gen);
	print("\tmentry=%d\n", de.mentry);
	print("\tmgen=%d\n", de.mgen);
	print("\tqid=%bd\n", de.qid);
	print("\tuid=%s\n", de.uid);
	print("\tgid=%s\n", de.gid);
	print("\tmid=%s\n", de.mid);
	print("\tmtime=%d\n", de.mtime);
	print("\tmcount=%d\n", de.mcount);
	print("\tctime=%d\n", de.ctime);
	print("\tatime=%d\n", de.atime);
	print("\tmode=%x\n", de.mode);
}

metablock(d: array of byte)
{
	mb := Metablock.unpack(d);
	if(mb == nil)
		error(sprint("unpacking metablock: %r"));
	printmetablock(mb, d, 0);
}

metablocks(d: array of byte)
{
	i := 0;
	while(i < len d) {
		mb := Metablock.unpack(d[i:]);
		if(mb == nil)
			error(sprint("unpacking metablock: %r"));
		printmetablock(mb, d[i:], 1);
		i += Venti->Dsize;
	}
}

printmetablock(mb: ref Metablock, d: array of byte, printde: int)
{
	print("Metablock:\n");
	print("\tsize=%d\n", mb.size);
	print("\tfree=%d\n", mb.free);
	print("\tmaxindex=%d\n", mb.maxindex);
	print("\tnindex=%d\n", mb.nindex);

	print("Meta entries:\n");
	for(i := 0; i < mb.nindex; i++) {
		me := Metaentry.unpack(d, i);
		if(me == nil)
			error(sprint("parsing meta entry: %r"));
		print("\toffset=%d size=%d\n", me.offset, me.size);
	}

	if(!printde)
		return;

	for(i = 0; i < mb.nindex; i++) {
		me := Metaentry.unpack(d, i);
		if(me == nil)
			error(sprint("parsing meta entry: %r"));
		de := Direntry.unpack(d[me.offset:me.offset+me.size]);
		if(de == nil)
			error(sprint("parsing direntry: %r"));
		printdirentry(de);
	}
}

pointers(d: array of byte)
{
	if(len d % Scoresize != 0)
		error(sprint("data not multiple of scoresize: %d", len d));
	print("Pointers:\n");
	for(o := Scoresize; o <= len d; o += Scoresize)
		print("\t%s\n", Score(d[o-Scoresize:o]).text());
}

rpointers(d: array of byte)
{
	esize := Scoresize+8;
	if(len d % esize != 0)
		error(sprint("data not multiple of scoresize+8: %d", len d));
	print("Rpointers:\n");
	for(o := 0; o+esize <= len d; o += esize)
		print("\tlength=%10bd %s\n", g64(d, o+Scoresize), Score(d[o:o+Scoresize]).text());
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
	b1 := (((((int f[i+4] << 8) | int f[i+5]) << 8) | int f[i+6]) << 8) | int f[i+7];
	return (big b0 << 32) | (big b1 & 16rFFFFFFFF);
}

error(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}
