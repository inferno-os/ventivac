implement Ventiwrite;

include "sys.m";
include "draw.m";
include "arg.m";
include "venti.m";

sys: Sys;
venti: Venti;

print, sprint, fprint, fildes: import sys;
Score, Session: import venti;

Ventiwrite: module {
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

	vtype := Venti->Datatype;
	arg->init(args);
	arg->setusage(arg->progname() + " [-d] [-a addr] [-t type]");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		't' =>	vtype = int arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 0)
		arg->usage();

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

	d := read();
	say(sprint("have data, length %d", len d));
	if(len d > Venti->Maxlumpsize)
		error(sprint("data (%d bytes) exceeds maximum lumpsize (%d bytes)", len d, Venti->Maxlumpsize));

	(ok, score) := session.write(vtype, d);
	if(ok < 0)
		error(sprint("writing data: %r"));
	say(sprint("wrote data to venti, length %d", len d));
	print("venti/read %d %s\n", vtype, score.text());
	if(session.sync() < 0)
		error(sprint("syncing server: %r"));
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
