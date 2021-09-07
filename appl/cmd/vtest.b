implement Vtest;

include "sys.m";
include "draw.m";
include "arg.m";
include "venti.m";

sys: Sys;
venti: Venti;

print, sprint, fprint, fildes: import sys;
Vmsg, Score, Session, Datatype: import venti;

Vtest: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;
dtype := Datatype;
n := 1;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	venti = load Venti Venti->PATH;
	venti->init();

	arg->init(args);
	arg->setusage(arg->progname() + " [-d] [-a addr] [-n count] type score");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		'n' =>	n = int arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();

	dtype = int hd args;
	args = tl args;
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

	for(i := 0; i < n; i++) {
		vmsg := ref Vmsg.Tread(1, i % 256, score, dtype, Venti->Maxlumpsize);
		d := vmsg.pack();
		if(sys->write(fd, d, len d) != len d)
			error(sprint("writing: %r"));
		say(sprint("> %d", tagof vmsg));
	}
	for(i = 0; i < n; i++) {
		(vmsg, err) := Vmsg.read(fd);
		if(err != nil)
			error(sprint("reading: %r"));
		say(sprint("< %d", tagof vmsg));
	}
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
