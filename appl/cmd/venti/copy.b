implement Venticopy;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
include "string.m";
include "venti.m";

str: String;
venti: Venti;

print, sprint, fprint, fildes: import sys;
Pointertype0, Pointertype6, Score, Session, Roottype, Dirtype, Datatype, Scoresize, Pointervarmask, Root, Rootsize, Entry, Entrysize, Entryactive, Entrydir: import venti;


Venticopy: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

dflag, fflag: int;
session: ref Session;
srcs, dsts: ref Session;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	venti = load Venti Venti->PATH;

	venti->init();

	arg->init(args);
	arg->setusage(sprint("%s [-df] srcaddr dstaddr [vac:]score", arg->progname()));
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		'f' =>	fflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 3)
		arg->usage();

	srcaddr := hd args;
	dstaddr := hd tl args;
	args = tl tl args;

	(tag, scorestr) := str->splitstrr(hd args, ":");
	if(tag != nil)
		tag = tag[:len tag-1];
	t: int;
	case tag {
	"vac" =>	t = Roottype;
	"entry" =>	t = Dirtype;
	* =>	fprint(fildes(2), "bad score type\n");
		arg->usage();
	}

	(sok, score) := Score.parse(scorestr);
	if(sok != 0)
		error("bad score: "+scorestr);
	say("have score");

	srcs = dial(srcaddr);
	dsts = dial(dstaddr);

	walk(score, t, 0);
	say("have walk");

	if(dsts.sync() < 0)
		error(sprint("syncing destination: %r"));
	say("synced");
}

walk(s: Score, t, dt: int)
{
	say(sprint("walk: %s/%d", s.text(), t));

	if(fflag && dsts.read(s, t, Venti->Maxlumpsize) != nil) {
		say(sprint("skipping %s/%d", s.text(), t));
		return;
	}

	d := srcs.read(s, t, Venti->Maxlumpsize);
	if(d == nil)
		error(sprint("reading %s/%d: %r", s.text(), t));

	case t {
	Roottype =>
		r := Root.unpack(d);
		if(r == nil)
			error(sprint("bad root: %r"));
		walk(r.score, Dirtype, 0);
		if(!isnul(*r.prev))
			walk(*r.prev, Roottype, 0);

	Dirtype =>
		for(o := 0; o+Entrysize <= len d; o += Entrysize) {
			e := Entry.unpack(d[o:o+Entrysize]);
			if(e == nil)
				error(sprint("bad entry: %r"));
			if(!(e.flags&Entryactive))
				continue;
			tvar := 0;
			if(e.flags & Venti->Entryvarblocks)
				tvar = Pointervarmask;
			nt := Datatype;
			if(e.flags&Entrydir)
				nt = Dirtype;
			if(e.depth == 0)
				walk(e.score, nt, 0);
			else
				walk(e.score, tvar|Pointertype0-1+e.depth, nt);
		}
		
	Pointertype0 to Pointertype6 =>
		nt := t-1;
		for(o := 0; o+Scoresize <= len d; o += Scoresize) {
			ns := Score(d[o:o+Scoresize]);
			if(ns.eq(Score.zero()))
				continue;
			if(t == Pointertype0)
				nt = dt;
			walk(ns, nt, dt);
		}

	Pointertype0+Pointervarmask to Pointertype6+Pointervarmask =>
		nt := t-1;
		for(o := 0; o+Scoresize+8 <= len d; o += Scoresize+8) {
			ns := Score(d[o:o+Scoresize]);
			if(ns.eq(Score.zero()))
				continue;
			if(t == Pointertype0|Pointervarmask)
				nt = dt;
			walk(ns, nt, dt);
		}

	Datatype =>
		;

	* =>
		error(sprint("unknown block type, %s/%d", s.text(), t));
	}
	
	(ok, ns) := dsts.write(t, d);
	if(ok < 0)
		error(sprint("writing %s/%d: %r", ns.text(), t));
	if(!ns.eq(s))
		error(sprint("destination returned different score: %s versus %s", s.text(), ns.text()));
}

isnul(s: Score): int
{
	for(i := 0; i < len s.a; i++)
		if(s.a[i] != byte 0)
			return 0;
	return 1;
}

dial(addr: string): ref Session
{
	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	session = Session.new(conn.dfd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");
	return session;
}

error(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}

say(s: string)
{
	if(dflag)
		fprint(fildes(2), "%s\n", s);
}
