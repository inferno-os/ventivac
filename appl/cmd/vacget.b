implement Vacget;

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
Score, Session: import venti;
Direntry, Modeperm, Modeappend, Modeexcl, Modedir, Modesnapshot, Vacdir, Vacfile: import vac;

Vacget: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
Dflag := vflag := pflag := tflag := 0;
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
	arg->setusage(sprint("%s [-Dptv] [-a addr] vacfile", arg->progname()));
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	addr = arg->earg();
		'D' =>	Dflag++;
		'p' =>	pflag++;
		't' =>	tflag++;
		'v' =>	vflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	(nil, score, serr) := vac->readscore(hd args);
	if(serr != nil)
		error("reading score: "+serr);
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

	(vd, nil, err) := vac->openroot(session, *score);
	if(err != nil)
		error(err);

	say("starting walk");
	walk(".", vd);
}

create(path: string, omode: int, de: ref Direntry): ref Sys->FD
{
	perm := Sys->DMDIR | Sys->DMAPPEND | Sys->DMEXCL | Sys->DMTMP;
	perm &= de.emode;
	perm |= 8r666;
	if(de.emode & Sys->DMDIR)
		perm |= 8r777;
	fd := sys->create(path, omode, perm);
	if(fd == nil)
		return nil;
	if(pflag) {
		d := sys->nulldir;
		d.uid = de.uid;
		d.gid = de.gid;
		d.mode = de.emode;
		if(sys->fwstat(fd, d) != 0) {
			fprint(fildes(2), "fwstat %s for uid/gid/mode: %r", path);
			d.uid = d.gid = "";
			sys->fwstat(fd, d);
		}
	}
	return fd;
}

walk(path: string, vd: ref Vacdir)
{
	say("start of walk: "+path);
	for(;;) {
		(n, de) := vd.readdir();
		if(n < 0)
			error(sprint("reading direntry in %s: %r", path));
		if(n == 0)
			break;
		say("walk: have direntry, elem="+de.elem);
		newpath := path+"/"+de.elem;
		(e, me) := vd.open(de);
		if(e == nil)
			error(sprint("reading entry for %s: %r", newpath));

		oflags := de.mode&~(Modeperm|Modeappend|Modeexcl|Modedir|Modesnapshot);
		if(oflags)
			fprint(fildes(2), "%s: not all bits in mode can be set: 0x%x", newpath, oflags);

		if(tflag || vflag)
			fprint(fildes(2), "%s\n", newpath);

		if(me != nil) {
			if(!tflag)
				create(newpath, Sys->OREAD, de);
				# ignore error, possibly for already existing dir.  
				# if creating really failed, writing files in the dir will fail later on.
			walk(newpath, Vacdir.new(session, e, me));
		} else {
			if(tflag)
				continue;
			say("writing file");
			fd := create(newpath, sys->OWRITE, de);
			if(fd == nil)
				error(sprint("creating %s: %r", newpath));
			bio := bufio->fopen(fd, bufio->OWRITE);
			if(bio == nil)
				error(sprint("bufio fopen %s: %r", newpath));

			buf := array[sys->ATOMICIO] of byte;
			vf := Vacfile.new(session, e);
			for(;;) {
				rn := vf.read(buf, len buf);
				if(rn == 0)
					break;
				if(rn < 0)
					error(sprint("reading vac %s: %r", newpath));
				wn := bio.write(buf, rn);
				if(wn != rn)
					error(sprint("writing local %s: %r", newpath));
			}
			bok := bio.flush();
			bio.close();
			if(bok == bufio->ERROR || bok == bufio->EOF)
				error(sprint("bufio close: %r"));

			if(pflag) {
				d := sys->nulldir;
				d.mtime = de.mtime;
				if(sys->fwstat(fd, d) < 0)
					fprint(fildes(2), "fwstat %s for mtime: %r", newpath);
			}
			fd = nil;
		}
	}
}

error(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}

say(s: string)
{
	if(Dflag)
		fprint(fildes(2), "%s\n", s);
}
