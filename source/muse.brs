'
' TODO
'  - show errors for bad filenames
'  - show errors for missing tracks
'
function join(delim as string, list as object) as string
	if list.count() = 0 then return ""
	s = invalid
	for each token in list
		if s = invalid then
			s = token
		else
			s = s + delim + token
		end if
	end for
	return s
end function

function reverse(list as object) as object
	rlist = []
	for each item in list
		rlist.unshift(item)
	end for
	return rlist
end function

'-----------------------------------------------------------------

function _wrap(s as string, font as object, width as integer) as object
	w = font.getonelinewidth(s, width + 1)
	if w < width then return [s, w, invalid]

	re = createobject("roRegex", "\s+", "")
	tokens = re.split(s)

	s1 = tokens.shift()
	w1 = font.getonelinewidth(s1, width + 1)

	while tokens.count() > 0
		s2 = s1 + " " + tokens[0]
		w2 = font.getonelinewidth(s2, width + 1)
		if w2 > width then return [s1, w1, join(" ", tokens)]
		s1 = s2
		w1 = w2
		tokens.shift()
	end while

	return [s1, w1, invalid]
end function

function wrap(s as string, font as object, width as integer) as object
	lines = []
	while true
		s_ = _wrap(s, font, width)
		lines.push(s_)
		if s_[2] = invalid then return lines
		s = s_[2]
	end while
end function

function text_r(screen as object, s, x as integer, y as integer, rgba as integer, em as float, font as object) as integer
	if s = invalid then return y

	em = em * font.getonelineheight()
	lines = wrap(s, font, x)
	for each line in reverse(lines)
		y = y - em
		screen.drawtext(line[0], x - line[1], y, rgba, font)
	end for
	return y
end function

function text_c(screen as object, s as string, rgba as integer, font as object) as void
	w = font.getonelinewidth(s, 1280)
	h = font.getonelineheight()

	x = 360 - h
	y = (1280 - w) / 2

	screen.drawText(s, x, y, rgba, font)
end function

'-----------------------------------------------------------------

function yesno(p as boolean) as string
	if p then return "yes"
	return "no"
end function

'-----------------------------------------------------------------

function ancestors(tip as string, root as string) as object
	re = createobject("roRegex", "/[^/]+$", "")

	lst = []
	while tip <> "" and tip <> root
		lst.push(tip)
		tip = re.replace(tip, "")
	end while
	lst.push(root)

	return lst
end function

'-----------------------------------------------------------------

function normalize_track(track as object) as object
	if not track.doesexist("genre")  then track.genre  = invalid
	if not track.doesexist("year")   then track.year   = invalid
	if not track.doesexist("artist") then track.artist = "Unknown Artist"
	if not track.doesexist("album")  then track.album  = "Unknown Album"
	if not track.doesexist("title")  then track.title  = "Untitled"

	return track
end function

'-----------------------------------------------------------------

function new_player(root as string) as object
	this = {
		root    : root
		debug   : false

		fonts   : createobject("roFontRegistry")
		fs      : createobject("roFileSystem")

		screen  : createobject("roScreen", true) ' double-buffered
		port    : createobject("roMessagePort")

		player  : createobject("roAudioPlayer")
		paused  : false

		current : invalid
		history : []

		scroll  : 0
		tick    : 250
		timer   : createobject("roTimespan")
	}
	this.player.setmessageport(this.port)
	this.player.setloop(true)
	this.screen.setmessageport(this.port)
	this.screen.setalphaenable(true)

	' setup fonts for listings
	this.font = {
		small : this.fonts.getdefaultfont(30, false, false)
		large : this.fonts.getdefaultfont(60, true,  false)
	}

	this.background = function (path) as void
		if path = invalid then path = m.root

		m.screen.clear(&h00000000)
		m.backdrop = invalid
		for each dir in ancestors(path, m.root)
			png = "ext1:/" + dir + "/muse.png"
			if m.fs.exists(png) then
				m.backdrop = createobject("roBitMap", png)
				exit for
			end if
		end for

		if m.backdrop = invalid then
			m.backdrop = createobject("roBitMap", "pkg:/assets/img/default.png")
		end if

		m.screen.drawobject(0, 0, m.backdrop)
	end function

	this.dimmer = function () as void
		m.screen.drawrect(0, 0, m.screen.getwidth(), m.screen.getheight(), &h000000dd)
	end function

	this.listing = function (lst as object, fn=invalid) as void
		if fn = invalid then
			fn = function (x as object) as string
				if x = invalid then return ""
				if x.doesexist("name")    then return x.name
				if x.doesexist("title")   then return x.title
				if x.doesexist("display") then return x.display
			end function
		end if

		INDENT = 20
		x = 20
		y = 20

		'-------------------------------------------
		' ...
		' ...
		' ...
		' Unfocused Item
		' Unfocused Item 2
		' FOCUSED ITEM IN LARGE FONT HERE
		' Unfocused Item 3
		' (10px gutter)
		'-------------------------------------------

		' Each unfocused item, in small font, is 30px tall
		' The focused item, in large font, is 65px tall

		'
		' That means the Y-offset of the focused item is
		'    720 - 10 - 30 - 65 = 625px
		'
		' And the area above the focused item (625px) affords
		' enough room to show 20 (600 / 30) preceding items
		' (or the tail end of the list, if we wrapped around)

		' Draw the Focused Item
		m.screen.drawtext(fn(lst.items[lst.current]), INDENT, 625, &hFFFFFFFF, m.font.large)

		' Draw the preceding items
		y = 625 - 30
		for i = 0 to 20
			idx = lst.current - 1 - i
			if idx < 0 then
				idx = lst.items.count() + idx
				if idx <= lst.current then exit for
			end if
			m.screen.drawtext(fn(lst.items[idx]), INDENT, y, &hFFFFFFFF, m.font.small)
			y = y - 30
		end for

		' Draw the following item
		idx = lst.current + 1
		if idx >= lst.items.count() then idx = 0
		if idx <> lst.current then
			m.screen.drawtext(fn(lst.items[idx]), INDENT, 625 + 65, &hFFFFFFFF, m.font.small)
		end if
	end function

	this.title = function (track as object) as void
		color = &hFFFFFFFF
		m.screen.drawtext(track.artist, 20, 20, color, m.font.small)
		m.screen.drawtext(track.title,  20, 50, color, m.font.large)
	end function

	this.show = function () as void
		m.screen.swapbuffers()
	end function

	this.redraw = function (delta=invalid) as void
		if m.vis <> invalid and m.doesexist(m.vis.screen) then
			m[m.vis.screen](m.vis.info, delta)
		end if
	end function

	this.event_loop = function () as void
		while true
			msg = wait(m.tick, m.port)
			if msg = invalid then
				if m.scroll <> 0 then
					m.redraw(m.scroll)
					ms = m.timer.totalmilliseconds()
					if ms > 5000 then
						m.tick = 1
					else if ms > 2000 then
						m.tick = 5
					else
						m.tick = 15
					end if
				end if

			else if type(msg) = "roUniversalControlEvent" then
				if m.vis <> invalid then
					if msg.getint() = 7 and m.playing <> invalid then ' replay
						m.history.push(m.vis)
						m.track_page(m.playing)
					end if

					if msg.getint() = 13 and m.playing <> invalid then ' play/pause
						if m.paused then
							m.player.resume()
						else
							m.player.pause()
						end if
						m.paused = not m.paused
					end if

					if msg.getint() = 6 then              ' select
						kids = m.vis.info.children
						if m.vis.info.type = "tracks" then
							m.history.push(m.vis)
							m.play(m.vis.info)

						else
							' menu selection
							m.go(kids.items[kids.current].path)
						end if
					end if


					if m.vis <> invalid and m.vis.screen = "track_page" then
						if msg.getint() = 0 then m.back() ' back
						if msg.getint() = 4 then ' left
							m.playing.children.current = offset(m.playing.children, -1)
							m.play(m.playing)
						end if
						if msg.getint() = 5 then ' right
							m.playing.children.current = offset(m.playing.children, 1)
							m.play(m.playing)
						end if

					else if m.vis <> invalid and m.vis.screen = "listing_page" then
						if msg.getint() = 0 or msg.getint() = 4 then m.back() ' back / left

						if msg.getint() = 102 or msg.getint() = 103 then
							m.scroll = 0
							m.tick = 250
						end if
						if msg.getint() = 2   or msg.getint() = 3   then
							m.timer.mark()
							m.scroll = 1
							if msg.getint() = 2 then m.scroll = -1
							m.redraw(m.scroll)
						end if
					end if
				end if

			else if type(msg) = "roAudioPlayerEvent" then
				if msg.islistitemselected() then
					' moved to the next track
					if m.debug then print "moved on to track #"; msg.getindex() - 1
					m.playing.children.current = msg.getindex()
					if m.vis <> invalid and m.vis.screen = "track_page" then
						m.track_page(m.playing)
					end if

				else if m.debug and msg.getmessage() = "startup progress" then
					print "starting up ... "; msg.getindex() / 10; "% done"

				else if m.debug
					print " audio player event: ["; msg.getmessage(); "]"
					print "  failed / succeeded?  : "; yesno(msg.isrequestfailed()); " / "; yesno(msg.isrequestsucceeded())
					print "  full / partial?      : "; yesno(msg.isfullresult());    " / "; yesno(msg.ispartialresult())
					print "  list item selected?  : "; yesno(msg.islistitemselected())
					print "  index                : "; msg.getindex()
				end if

				if msg.isrequestfailed() then m.player.stop()

			else if m.debug
				print "received a " type(msg) " message"

			end if
		end while
	end function

	this.listing_page = function (info as object, delta=invalid) as void
		info.children.current = offset(info.children, delta)
		m.vis = {
			screen : "listing_page"
			info   : info
		}

		m.background(info.root)
		m.dimmer()
		m.listing(info.children)
		m.show()
	end function

	this.error_page = function (msg as string) as void
		m.screen.clear(&h330000FF)
		text_c(m.screen, msg, &hFFFFFFFF, m.font.small)
		m.show()
	end function

	this.track_page = function (info as object) as void
		m.vis = {
			screen : "track_page"
			info   : info
		}

		cover = invalid
		if m.fs.exists("ext1:/" + info.root + "/muse.png") then
			cover = createobject("roBitMap", "ext1:/" + info.root + "/muse.png")
		else
			cover = createobject("roBitMap", "pkg:/assets/img/album.png")
		end if

		m.screen.clear(&h000000ff)
		m.screen.drawobject(640 + 10, 115, cover)

		track = normalize_track(info.children.items[info.children.current])
		x = 640 - 10
		y = 115 + 400
		y = text_r(m.screen, track.genre,   x, y, &hFFFFFFFF, 1.0, m.font.small)
		y = text_r(m.screen, track.year,    x, y, &hFFFFFFFF, 1.0, m.font.small)
		y = text_r(m.screen, track.artist,  x, y, &hFFFFFFFF, 1.0, m.font.small)
		y = text_r(m.screen, track.name,    x, y, &hFFFFFFFF, 1.0, m.font.small)
		y = text_r(m.screen, track.title,   x, y, &hFFFFFFFF, 1.2, m.font.large)

		m.show()
	end function

	this.play = function (info as object) as void
		m.playing = info

		tracks = info.children.items
		m.player.stop()
		m.player.clearcontent()
		for each track in info.children.items
			m.player.addcontent({
				url          : "ext1:/" + track.path
				streamformat : "flac"                     ' FIXME
			})
		end for
		m.player.setnext(info.children.current)
		m.player.play()
		m.paused = false

		m.track_page(info)
	end function

	this.lookup = function (path as string) as object
		jsonfile = "ext1:/" + path + "/muse.json"
		if not m.fs.exists(jsonfile) then return invalid

		data = parsejson(readasciifile(jsonfile))
		if not data.doesexist("children") then
			data.children = {
				current : 0
				items   : []
			}
		end if
		if not data.children.doesexist("current") then
			data.children.current = 0
		end if
		data.root = path
		return data
	end function

	this.go = function (path as string) as void
		if m.vis <> invalid then m.history.push(m.vis)

		info = m.lookup(path)
		if info <> invalid then
			m.listing_page(info)
		else
			m.error_page("No metadata found in" + path)
		end if
	end function

	this.back = function () as void
		vis = m.history.pop()
		if vis <> invalid then
			if vis.screen = "listing_page" then m.listing_page(vis.info)
			if vis.screen = "track_page"   then m.track_page(vis.info)
		end if
	end function

	return this
end function

function offset(lst as object, delta=invalid) as integer
	n = lst.current
	if n = invalid then n = 0
	if delta = invalid then return n

	n = n + delta
	if n < 0                  then return lst.items.count() - 1
	if n >= lst.items.count() then return 0
	return n
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

function main() as void
	p = new_player("/")
	p.go("/")
	p.event_loop()
end function

' EVENT CODES     down      up
' -----------     ----     ---
' back               0     100
' up                 2     102
' down               3     103
' left               4     104
' right              5     105
' select             6     106
' replay             7     107
' rewind             8     108
' forward            9     109
' info              10     113
' play              13     113
