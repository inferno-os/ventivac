implement Vacfs;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "string.m";
include "daytime.m";
include "venti.m";
include "vac.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";

str: String;
daytime: Daytime;
venti: Venti;
vac: Vac;
styxservers: Styxservers;

print, sprint, fprint, fildes: import sys;
Score, Session: import venti;
Direntry, Vacdir, Vacfile: import vac;
Styxserver, Fid, Navigator, Navop: import styxservers;

Vacfs: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

addr := "net!$venti!venti";
dflag := pflag := 0;
session: ref Session;

srv: ref Styxserver;

Elem: adt {
	qid:	int;
	de: 	ref Direntry;
	size:	big;
	pick {
	File =>	vf: 	ref Vacfile;
	Dir =>	vd:	ref Vacdir;
		pqid:	int;
		prev:	(int, ref Sys->Dir);	# last returned Dir to Readdir
	}

	mkdir:	fn(qid: int, de: ref Direntry, size: big, vd: ref Vacdir, pqid: int): ref Elem.Dir;
	new:	fn(nqid: int, vd: ref Vacdir, de: ref Direntry, pqid: int): ref Elem;
	stat:	fn(e: self ref Elem): ref Sys->Dir;
};

# maps vacfs dir qid to (vac qid, vacfs qid) of files in that dir
Qidmap: adt {
	qid:	int;
	cqids:	list of (big, int);
};

# path that has been walked to
Path: adt {
	path, nused:	int;
	elems:	list of ref Elem;
};

Qfakeroot:	con 0;

lastqid := 0;
qidmaps := array[512] of list of ref Qidmap;
scoreelems: list of (string, ref Elem.Dir);
rootelem: ref Elem;

curelems: list of ref Elem;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;
	venti = load Venti Venti->PATH;
	styx = load Styx Styx->PATH;
	styxservers = load Styxservers Styxservers->PATH;
	vac = load Vac Vac->PATH;

	venti->init();
	vac->init();
	styx->init();
	styxservers->init(styx);

	arg->init(args);
	arg->setusage(arg->progname()+" [-Ddp] [-a addr] [vacfile]");
	while((ch := arg->opt()) != 0)
		case ch {
		'D' =>	styxservers->traceset(1);
		'a' =>	addr = arg->earg();
		'd' =>	dflag++;
		'p' =>	pflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args > 1)
		arg->usage();

	score: ref Score;
	if(len args == 1) {
		err: string;
		(nil, score, err) = vac->readscore(hd args);
		if(err != nil)
			error("reading score: "+err);
	}

	(cok, conn) := sys->dial(addr, nil);
	if(cok < 0)
		error(sprint("dialing %s: %r", addr));
	say("have connection");

	session = Session.new(conn.dfd);
	if(session == nil)
		error(sprint("handshake: %r"));
	say("have handshake");

	if(args == nil) {
		de := Direntry.new();
		de.uid = de.gid = de.mid = "vacfs";
		de.ctime = de.atime = de.mtime = daytime->now();
		de.mode = Vac->Modedir|8r555;
		de.emode = Sys->DMDIR|8r555;
		rootelem = Elem.mkdir(Qfakeroot, de, big 0, nil, Qfakeroot);
	} else {
		(vd, de, err) := vac->openroot(session, *score);
		if(err != nil)
			error(err);
		qid := ++lastqid;
		rootelem = Elem.mkdir(qid, de, big 0, vd, qid);
	}

	navchan := chan of ref Navop;
	nav := Navigator.new(navchan);
	spawn navigator(navchan);

	msgc: chan of ref Tmsg;
	(msgc, srv) = Styxserver.new(sys->fildes(0), nav, big rootelem.qid);

serve:
	while((mm := <-msgc) != nil)
		pick m := mm {
		Readerror =>
			fprint(fildes(2), "styx read: %s\n", m.error);
			break serve;

		Attach =>
			f := srv.attach(m);
			if(f != nil) {
				p := getpath(int f.path);
				if(p == nil)
					putpath(p = ref Path(int f.path, 0, rootelem::nil));
				p.nused++;
			}

		Read =>
			if(dflag) say(sprint("have read, offset=%ubd count=%d", m.offset, m.count));
			(f, err) := srv.canread(m);
			if(f == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				continue;
			}
			if(f.qtype & Sys->QTDIR){
				srv.default(m);
				continue;
			}

			p := getpath(int f.path);
			file: ref Elem.File;
			pick e := hd p.elems {
			File =>	file = e;
			Dir =>	srv.reply(ref Rmsg.Error(m.tag, "internal error"));
				continue;
			}
			n := m.count;
			a := array[n] of byte;
			have := file.vf.pread(a, n, m.offset);
			if(have < 0) {
				srv.reply(ref Rmsg.Error(m.tag, sprint("%r")));
				continue;
			}
			srv.reply(ref Rmsg.Read(m.tag, a[:have]));

		Walk =>
			f := srv.getfid(m.fid);
			if(f == nil) {
				srv.reply(ref Rmsg.Error(m.tag, styxservers->Ebadfid));
				continue;
			}
			p := getpath(int f.path);
			curelems = p.elems;
			nf := srv.walk(m);
			if(nf != nil) {
				if(nf.fid == f.fid) {
					if(--p.nused <= 0)
						delpath(p);
				}
				putpath(p = ref Path(int nf.path, 0, curelems));
				p.nused++;
			}
			curelems = nil;

		Open =>
			(f, mode, d, err) := canopen(m);
			if(f == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				continue;
			}
			f.open(mode, d.qid);
			srv.reply(ref Rmsg.Open(m.tag, d.qid, srv.iounit()));

		Clunk or Remove =>
			f := srv.getfid(m.fid);
			if(f != nil) {
				p := getpath(int f.path);
				if(--p.nused <= 0)
					delpath(p);
			}
			if(tagof m == tagof Tmsg.Remove)
				srv.reply(ref Rmsg.Error(m.tag, styxservers->Eperm));
			else
				srv.default(m);

		* =>
			srv.default(m);
		}
	navchan <-= nil;
}

# from appl/lib/styxservers.b
canopen(m: ref Tmsg.Open): (ref Fid, int, ref Sys->Dir, string)
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return (nil, 0, nil, Styxservers->Ebadfid);
	if(c.isopen)
		return (nil, 0, nil, Styxservers->Eopen);
	(f, err) := srv.t.stat(c.path);
	if(f == nil)
		return (nil, 0, nil, err);
	mode := styxservers->openmode(m.mode);
	if(mode == -1)
		return (nil, 0, nil, Styxservers->Ebadarg);
	if(mode != Sys->OREAD && f.qid.qtype & Sys->QTDIR)
		return (nil, 0, nil, Styxservers->Eperm);
	if(!pflag && !styxservers->openok(c.uname, m.mode, f.mode, f.uid, f.gid))
		return (nil, 0, nil, Styxservers->Eperm);
	if(m.mode & Sys->ORCLOSE)
		return (nil, 0, nil, Styxservers->Eperm);
	return (c, mode, f, err);
}

navigator(c: chan of ref Navop)
{
	while((navop := <-c) != nil)
		pick n := navop {
		Stat =>
			e := rootelem;
			if(int n.path != rootelem.qid) {
				p := getpath(int n.path);
				if(p != nil) {
					e = hd p.elems;
				} else if(curelems != nil && (hd curelems).qid == int n.path) {
					e = hd curelems;
				} else {
					n.reply <-= (nil, "internal error");
					continue;
				}
			}
			n.reply <-= (e.stat(), nil);

		Walk =>
			(e, err) := walk(int n.path, n.name);
			if(err != nil) {
				n.reply <-= (nil, err);
				continue;
			}
			n.reply <-= (e.stat(), nil);

		Readdir =>
			if(dflag) say(sprint("have readdir path=%bd offset=%d count=%d", n.path, n.offset, n.count));
			if(n.path == big Qfakeroot) {
				n.reply <-= (nil, nil);
				continue;
			}

			p := getpath(int n.path);
			e: ref Elem.Dir;
			pick ee := hd p.elems {
			Dir =>	e = ee;
			File =>	n.reply <-= (nil, "internal error");
				continue;
			}
			if(n.offset == 0) {
				e.vd.rewind();
				e.prev = (-1, nil);
			}

			# prev is needed because styxservers can request the previously returned Dir
			(loffset, d) := e.prev;
			if(n.offset == loffset+1) {
				(ok, de) := e.vd.readdir();
				if(ok < 0) {
					say(sprint("readdir error: %r"));
					n.reply <-= (nil, sprint("reading directory: %r"));
					continue;
				}
				if(de != nil) {
					cqid := qidget(e.qid, de.qid);
					if(cqid < 0)
						cqid = qidput(e.qid, de.qid);
					ne := Elem.new(cqid, e.vd, de, e.qid);
					e.prev = (n.offset, ne.stat());
				} else {
					e.prev = (n.offset, nil);
				}
			} else if(n.offset != loffset)
				error("internal error");
			(nil, d) = e.prev;
			if(d != nil)
				n.reply <-= (d, nil);
			n.reply <-= (nil, nil);
		}
}

walk(path: int, name: string): (ref Elem, string)
{
	if(name == "..") {
		if(len curelems > 1)
			curelems = tl curelems;
		return (hd curelems, nil);
	}

	if(path == Qfakeroot) {
		e := scoreget(name);
		if(e == nil) {
			(ok, score) := Score.parse(name);
			if(ok != 0)
				return (nil, "bad score");

			(vd, de, err) := vac->openroot(session, score);
			if(err != nil)
				return (nil, err);

			e = Elem.mkdir(++lastqid, de, big 0, vd, rootelem.qid);
			scoreput(name, e);
		}
		curelems = e::curelems;
		return (hd curelems, nil);
	}

	pick e := hd curelems {
	File =>
		return (nil, styxservers->Enotdir);
	Dir =>
		de := e.vd.walk(name);
		if(de == nil)
			return (nil, sprint("%r"));
		cqid := qidget(e.qid, de.qid);
		if(cqid < 0)
			cqid = qidput(e.qid, de.qid);
		ne := Elem.new(cqid, e.vd, de, e.qid);
		curelems = ne::curelems;
		return (ne, nil);
	}
}

qidget(qid: int, vqid: big): int
{
	for(l := qidmaps[qid % len qidmaps]; l != nil; l = tl l) {
		if((hd l).qid != qid)
			continue;
		for(m := (hd l).cqids; m != nil; m = tl m) {
			(vq, cq) := hd m;
			if(vq == vqid)
				return cq;
		}
	}
	return -1;
}

qidput(qid: int, vqid: big): int
{
	qd: ref Qidmap;
	for(l := qidmaps[qid % len qidmaps]; l != nil; l = tl l)
		if((hd l).qid == qid) {
			qd = hd l;
			break;
		}
	if(qd == nil) {
		qd = ref Qidmap(qid, nil);
		qidmaps[qid % len qidmaps] = qd::nil;
	}
	qd.cqids = (vqid, ++lastqid)::qd.cqids;
	return lastqid;
}

scoreget(score: string): ref Elem.Dir
{
	for(l := scoreelems; l != nil; l = tl l) {
		(s, e) := hd l;
		if(s == score)
			return e;
	}
	return nil;
}

scoreput(score: string, e: ref Elem.Dir)
{
	scoreelems = (score, e)::scoreelems;
}

Elem.mkdir(qid: int, de: ref Direntry, size: big, vd: ref Vacdir, pqid: int): ref Elem.Dir
{
	return ref Elem.Dir(qid, de, size, vd, pqid, (-1, nil));
}

Elem.new(nqid: int, vd: ref Vacdir, de: ref Direntry, pqid: int): ref Elem
{
	(e, me) := vd.open(de);
	if(e == nil)
		return nil;
	if(de.mode & Vac->Modedir)
		return Elem.mkdir(nqid, de, e.size, Vacdir.new(session, e, me), pqid);
	return ref Elem.File(nqid, de, e.size, Vacfile.new(session, e));
}

Elem.stat(e: self ref Elem): ref Sys->Dir
{
	d := e.de.mkdir();
	d.qid.path = big e.qid;
	d.length = e.size;
	return d;
}


qidpaths := array[512] of list of ref Path;
nqidpaths := 0;

delpath(p: ref Path)
{
	i := p.path % len qidpaths;
	r: list of ref Path;
	for(l := qidpaths[i]; l != nil; l = tl l)
		if(hd l != p)
			r = hd l::r;
		else
			nqidpaths--;
	qidpaths[i] = r;
}

putpath(p: ref Path)
{
	i := p.path % len qidpaths;
	qidpaths[i] = p::qidpaths[i];
	nqidpaths++;
}

getpath(path: int): ref Path
{
	i := path % len qidpaths;
	for(l := qidpaths[i]; l != nil; l = tl l)
		if((hd l).path == path)
			return hd l;
	return nil;
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
