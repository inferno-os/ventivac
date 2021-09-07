implement Ventry;

include "sys.m";
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "venti.m";
include "vac.m";

sys: Sys;
venti: Venti;
vac: Vac;

print, sprint, fprint, fildes: import sys;
Score, Session, Entry, Entrysize, Datatype, Dirtype: import venti;
Vacfile: import vac;

Ventry: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;

	venti->init();
	vac->init();

	index := 0;
	arg->init(args);
	arg->setusage(arg->progname() + " [-d] [-a addr] [-i index] score");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		'i' =>	index = int arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	(ok, score) := Score.parse(hd args);
	if(ok != 0)
		error("bad score: "+hd args);

	say("dialing");
	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	fd := conn.dfd;
	say("have connection");

	session := Session.new(fd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	ed := session.read(score, Dirtype, venti->Maxlumpsize);
	if(ed == nil)
		error(sprint("reading entry: %r"));
	o := (index+1)*Entrysize;
	if(o > len ed)
		error(sprint("only %d entries present", len ed/Entrysize));
	e := Entry.unpack(ed[o-Entrysize:o]);
	if(e == nil)
		error(sprint("parsing entry: %r"));
	say("entry unpacked");

	bio := bufio->fopen(fildes(1), bufio->OWRITE);
	if(bio == nil)
		error(sprint("fopen stdout: %r"));

	f := Vacfile.new(session, e);
	buf := array[e.dsize] of byte;
	for(;;) {
		n := f.read(buf, len buf);
		if(n < 0)
			error(sprint("reading: %r"));
		if(n == 0)
			break;
		say(sprint("have %d", n));
		if(bio.write(buf, n) != n)
			error(sprint("writing: %r"));
	}
	if(bio.flush() < 0)
		error(sprint("closing: %r"));
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
