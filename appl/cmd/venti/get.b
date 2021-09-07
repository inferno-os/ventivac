implement Ventiget;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
include "string.m";
include "venti.m";
include "vac.m";

str: String;
venti: Venti;
vac: Vac;

print, sprint, fprint, fildes: import sys;
Score, Session, Entry, Entrysize, Dirtype, Datatype: import venti;
Vacfile: import vac;

Ventiget: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;
session: ref Session;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;

	venti->init();
	vac->init();

	arg->init(args);
	arg->setusage(sprint("%s [-d] [-a addr] [entry:]score", arg->progname()));
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	(tag, scorestr) := str->splitstrr(hd args, ":");
	if(tag != nil)
		tag = tag[:len tag-1];
	if(tag == nil)
		tag = "entry";
	if(tag != "entry")
		error("bad score type: "+tag);

	(sok, score) := Score.parse(scorestr);
	if(sok != 0)
		error("bad score: "+scorestr);
	say("have score");

	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	fd := conn.dfd;
	session = Session.new(fd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	d := session.read(score, Dirtype, Entrysize);
	if(d == nil)
		error(sprint("reading entry: %r"));
	e := Entry.unpack(d);
	if(e == nil)
		error(sprint("unpacking entry: %r"));
	say("have entry");

	bio := bufio->fopen(fildes(1), bufio->OWRITE);
	if(bio == nil)
		error(sprint("bufio fopen: %r"));

	say("reading");
	buf := array[sys->ATOMICIO] of byte;
	vf := Vacfile.new(session, e);
	for(;;) {
		rn := vf.read(buf, len buf);
		if(rn == 0)
			break;
		if(rn < 0)
			error(sprint("reading: %r"));
		wn := bio.write(buf, rn);
		if(wn != rn)
			error(sprint("writing: %r"));
	}
	bok := bio.flush();
	bio.close();
	if(bok == bufio->ERROR || bok == bufio->EOF)
		error(sprint("bufio close: %r"));
	say("done");
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
