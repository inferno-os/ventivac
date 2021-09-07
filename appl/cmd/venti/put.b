implement Ventiput;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
include "venti.m";
include "vac.m";
include "rabin.m";

venti: Venti;
vac: Vac;
rabin: Rabin;

print, sprint, fprint, fildes: import sys;
Score, Session, Entry, Dirtype, Datatype: import venti;
File: import vac;
Rcfg, Rfile: import rabin;

Ventiput: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := 0;
rflag := 0;
blocksize := Venti->Dsize;
session: ref Session;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg := load Arg Arg->PATH;
	venti = load Venti Venti->PATH;
	vac = load Vac Vac->PATH;
	rabin = load Rabin Rabin->PATH;

	venti->init();
	vac->init();
	rabin->init(bufio);

	prime := Vac->Rabinprime;
	mod := Vac->Rabinmod;
	width := Vac->Rabinwidth;
	blockmin := Vac->Rabinblockmin;
	blockmax := Vac->Rabinblockmax;

	arg->init(args);
	arg->setusage(sprint("%s [-dr] [-a addr] [-b blocksize]", arg->progname()));
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'b' =>	blocksize = int arg->earg();
		'r' =>	rflag++;
		'd' =>	dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 0)
		arg->usage();

	rcfg: ref Rcfg;
	if(rflag) {
		err: string;
		(rcfg, err) = Rcfg.mk(prime, width, mod);
		if(err != nil)
			error("rabincfg: "+err);
	}

	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	session = Session.new(conn.dfd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	bio := bufio->fopen(fildes(0), bufio->OREAD);
	if(bio == nil)
		error(sprint("bufio open: %r"));

        rfile: ref Rfile;
        if(rflag) {
                err: string;
                (rfile, err) = rabin->open(rcfg, bio, blockmin, blockmax);
                if(err != nil)
                        error("rabin open: "+err);
        }

	say("writing");
	f := File.new(session, Datatype, blocksize, rflag);
	for(;;) {
                if(rflag) {
			(d, nil, err) := rfile.read();
			if(err != nil)
				error("reading: "+err);
			if(len d == 0)
				break;
			if(f.write(d) < 0)
				error(sprint("writing: %r"));
		} else {
			buf := array[blocksize] of byte;
			n := 0;
			while(n < len buf) {
				want := len buf - n;
				have := bio.read(buf[n:], want);
				if(have == 0)
					break;
				if(have < 0)
					error(sprint("reading: %r"));
				n += have;
			}
			if(dflag) say(sprint("have buf, length %d", n));

			if(f.write(buf[:n]) < 0)
				error(sprint("writing: %r"));
			if(n != len buf)
				break;
		}
	}
	bio.close();
	e := f.finish();
	if(e == nil)
		error(sprint("flushing: %r"));
	d := e.pack();

	(rok, rscore) := session.write(Dirtype, d);
	if(rok < 0)
		error(sprint("writing root score: %r"));
	say("entry written, "+rscore.text());
	print("entry:%s\n", rscore.text());

	if(session.sync() < 0)
		error(sprint("syncing server: %r"));
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
