implement Ventiping;

include "sys.m";
include "draw.m";
include "arg.m";
include "venti.m";

sys: Sys;
venti: Venti;

print, sprint, fprint, fildes: import sys;
Score, Session, Vmsg: import venti;

Ventiping: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;
n := 3;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	venti = load Venti Venti->PATH;
	venti->init();

	arg->init(args);
	arg->setusage(arg->progname() + " [-d] [-a addr] [-n count]");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		'n' =>	n = int arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 0)
		arg->usage();

	say("dialing");
	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		fail(sprint("dialing %s: %r", addr));
	fd := conn.dfd;
	say("have connection");

	session := Session.new(fd);
	if(session == nil)
		fail(sprint("handshake: %r"));
	say("have handshake");

	tm := ref Vmsg.Tping(1, 0);
	i := 0;
	for(;;) {
		t0 := sys->millisec();
		(rm, err) := session.rpc(tm);
		if(rm == nil)
			fail("ping: "+err);
		t1 := sys->millisec();
		print("%d ms\n", t1-t0);
		i++;
		if(i == n)
			break;
		sys->sleep(1*1000);
	}
}

fail(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}

say(s: string)
{
	if(dflag)
		fprint(fildes(2), "%s\n", s);
}
