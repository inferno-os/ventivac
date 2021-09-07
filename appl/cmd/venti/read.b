implement Ventiread;

include "sys.m";
include "draw.m";
include "arg.m";
include "venti.m";

sys: Sys;
venti: Venti;

print, sprint, fprint, fildes: import sys;
Score, Session: import venti;

Ventiread: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	venti = load Venti Venti->PATH;
	venti->init();

	arg->init(args);
	arg->setusage(arg->progname() + " [-d] [-a addr] type score");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();

	stype := int hd args;
	(sok, score) := Score.parse(hd tl args);
	if(sok != 0)
		error("bad score: "+ hd tl args);

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

	d := session.read(score, stype, Venti->Maxlumpsize);
	if(d == nil)
		error(sprint("reading score: %r"));
	say(sprint("have data, length %d", len d));
	sys->write(fildes(1), d, len d);
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
