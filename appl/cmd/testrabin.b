implement Testrabin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import Bufio;
include "keyring.m";
	keyring: Keyring;
include "rabin.m";
	rabin: Rabin;

print, sprint, fprint, fildes: import sys;
Rcfg, Rfile: import rabin;

dflag, vflag: int;
modfile: string;

Testrabin: module {
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	keyring = load Keyring Keyring->PATH;

	p := 269;
	m := 8*1024;
	n := 31;
	min := 1024;
	max := 32*1024;

	modfile = Rabin->PATH;

	arg->init(args);
	arg->setusage(arg->progname()+" [-dv] [-f rabin.dis] [-p prime] [-n width] [-m mod] [-s min] [-S max] file");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		'v' =>	vflag++;
		'f' =>	modfile = arg->earg();
		'p' =>	p = int arg->earg();
		'n' =>	n = int arg->earg();
		'm' =>	m = int arg->earg();
		's' =>	min = int arg->earg();
		'S' =>	max = int arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();

	rabin = load Rabin modfile;
	if(rabin == nil)
		fail(sprint("loading module rabin %s: %r", modfile));
	rabin->init(bufio);

	if(len args != 1)
		arg->usage();
	rabin->debug = dflag;

	(rcfg, rerr) := Rcfg.mk(p, n, m);
	if(rerr != nil)
		fail("rabincfg: "+rerr);

	b := bufio->open(hd args, Bufio->OREAD);
	if(b == nil)
		fail(sprint("open: %r"));
	(rfile, oerr) := rabin->open(rcfg, b, min, max);
	if(oerr != nil)
		fail("rfile open: "+oerr);

	nblocks := 0;
	nbytes := 0;
	for(;;) {
		(d, off, err) := rfile.read();
		if(err != nil)
			fail("rfile read: "+err);
		if(len d == 0)
			break;
		nblocks++;
		nbytes += len d;
		if(vflag) {
			score := sha1(d);
			print("offset=%bd, score=%s len=%d\n", off, score, len d);
		}
	}
	mean := 0;
	if(nblocks > 0)
		mean = nbytes/nblocks;
	print("%d blocks, %d mean block size\n", nblocks, mean);
}

sha1(a: array of byte): string
{
	r := array[keyring->SHA1dlen] of byte;
	keyring->sha1(a, len a, r, nil);
	s := "";
	for(i := 0; i < len r; i++)
		s += sprint("%02x", int r[i]);
	return s;
}

fail(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}
