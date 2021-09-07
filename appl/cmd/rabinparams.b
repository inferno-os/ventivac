implement Rabinparams;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "rabin.m";
	rabin: Rabin;

print, sprint, fprint, fildes: import sys;
Rcfg, Rfile: import rabin;

bflag, Bflag, dflag, vflag, iflag: int;
prime, mod, width, min, max: int;
rcfg: ref Rcfg;
berr: ref Iobuf;

totalbytes, blocks: big;
blocksizes: array of int;
bounds: array of array of (array of byte, int);

Rabinparams: module {
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	rabin = load Rabin Rabin->PATH;
	if(rabin == nil)
		fail(sprint("loading module rabin %s: %r", Rabin->PATH));
	rabin->init(bufio);

	prime = 269;
	mod = 8*1024;
	width = 31;
	min = 1024;
	max = 32*1024;

	arg->init(args);
	arg->setusage(arg->progname()+" [-bBdiv] [-p prime] [-n width] [-m mod] [-s min] [-S max] dir ...");
	while((c := arg->opt()) != 0)
		case c {
		'b' =>	bflag++;
		'B' =>	Bflag++;
		'd' =>	dflag++;
		'i' =>	iflag++;
		'p' =>	prime = int arg->earg();
		'n' =>	width = int arg->earg();
		'm' =>	mod = int arg->earg();
		's' =>	min = int arg->earg();
		'S' =>	max = int arg->earg();
		'v' =>	vflag++;
		* =>	arg->usage();
		}
	args = arg->argv();

	if(len args == 0)
		arg->usage();
	rabin->debug = dflag;

	blocks = big 0;
	blocksizes = array[max] of {* => 0};
	bounds = array[256] of array of (array of byte, int);

	rerr: string;
	(rcfg, rerr) = Rcfg.mk(prime, width, mod);
	if(rerr != nil)
		fail("rabincfg: "+rerr);

	if(bflag) {
		berr = bufio->fopen(fildes(2), Bufio->OWRITE);
		if(berr == nil)
			fail(sprint("bufio open stderr: %r"));
	}

	for(; args != nil; args = tl args)
		walk(hd args);
	if(berr != nil)
		berr.close();

	if(Bflag) {
		for(i := 0; i < len blocksizes; i++)
			if(blocksizes[i] == 0)
				continue;
			else
				print("%10d  %d\n", i, blocksizes[i]);
	}
	if(vflag > 1) {
		nbounds := 0;
		for(i := 0; i < len bounds; i++) {
			for(j := 0; j < len bounds[i]; j++)
				fprint(fildes(2), "%-20s %d\n", fmtbound(bounds[i][j].t0), bounds[i][j].t1);
			nbounds += len bounds[i];
		}
		fprint(fildes(2), "nbounds=%d\n", nbounds);
	}
	print("blocks=%bd\n", blocks);
	mean := 0;
	if(blocks != big 0)
		mean = int (totalbytes/blocks);
	print("meanblocksize=%d\n", mean);
}

walk(path: string)
{
	if(vflag)
		print("walk %s\n", path);
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		if(iflag)
			return;
		fail(sprint("opening %s: %r", path));
	}
	(ok, dir) := sys->fstat(fd);
	if(ok < 0)
		fail(sprint("fstat %s: %r", path));
	if(dir.mode & Sys->DMDIR) {
		for(;;) {
			(n, d) := sys->dirread(fd);
			if(n == 0)
				break;
			if(n < 0)
				fail(sprint("dirread %s: %r", path));
			for(i := 0; i < n; i++)
				walk(path+"/"+d[i].name);
		}
	} else {
		b := bufio->fopen(fd, Bufio->OREAD);
		if(b == nil)
			fail(sprint("bufio open %s: %r", path));
		(rfile, oerr) := rabin->open(rcfg, b, min, max);
		if(oerr != nil)
			fail("rfile open: "+oerr);

		i := 0;
		for(;;) {
			(d, nil, err) := rfile.read();
			if(err != nil)
				fail("rfile read: "+err);
			if(len d == 0)
				break;
			if(i > 0 && len d > min && len d < max)
				note(d[:width], len d);
			i++;
		}
		b.close();
	}
}

eq(d1, d2: array of byte): int
{
	if(len d1 != len d2)
		return 0;
	for(i := 0; i < len d1; i++)
		if(d1[i] != d2[i])
			return 0;
	return 1;
}

note(d: array of byte, n: int)
{
	totalbytes += big n;
	blocks++;
	blocksizes[n]++;
	buck := int d[0];
	if(vflag > 1) {
		for(i := 0; i < len bounds[buck]; i++) {
			if(eq(bounds[buck][i].t0, d)) {
				bounds[buck][i].t1++;
				return;
			}
		}
		nb := array[len bounds[buck]+1] of (array of byte, int);
		nb[:] = bounds[buck];
		nb[len bounds[buck]] = (d, 1);
		bounds[buck] = nb;
	}
	if(berr != nil)
		berr.puts(sprint("%-20s\n", fmtbound(d)));
}

fmtbound(d: array of byte): string
{
	s := "";
	for(i := 0; i < len d; i++) {
		if(d[i] >= byte 16r20 && d[i] <= byte 16r7f)
			s += sprint("%c", int d[i]);
		else
			s += sprint("\\x%02x", int d[i]);
	}
	return "\""+s+"\"";
}

fail(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}
