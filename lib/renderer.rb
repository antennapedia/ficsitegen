#-------------------------------------------------------------------------------
# page renderer, page generation functions

class Page
	# Intended to be a more general page renderer
	# don't need to repeat code to generate common page requirements
	
	attr_writer :details
	attr_accessor :path
	attr_accessor :prerequisites
	attr_accessor :keywords
	attr_accessor :message

	def initialize(tmpl='index.haml', msg=nil, dest='pattern', perq=[])
		@template = Haml::Engine.new(File.open($templates + tmpl).read, options = { :format => :html5, :ugly => false })
		@message = msg
		@path = File::join($output, dest)
		@prerequisites = perq
		@keywords = {}
	end
	
	def applyDestinationPattern(args)
		@path = @path % args
	end
	
	def render
		puts @message if @message != nil
		self.generatePrereqs([])
		fp = File.new(@path, 'w')
		fp.puts @template.render( @keywords)
		fp.close
	end
	
	def generatePrereqs(args)
		@prerequisites = @prerequisites | args
		@keywords['_page'] = self

		@prerequisites.each do |item|
			if item == 'site'
				@keywords[item] = Site.default
			elsif item == 'fandoms'
				@keywords[item] = Fandom.allSorted
			elsif item == 'stories'
				@keywords[item] = Story.allSorted
			elsif item == 'latest'
				@keywords[item] = Story.fetchRecent(10)
			elsif item == 'datestamp'
				@keywords[item] = Time.now.strftime("%a, %d %b %Y %H:%M%p")
			else
				puts item
			end
		end
	end
	
	def include(tmpl, args)
		partial = Haml::Engine.new(File.open($templates + tmpl).read)
		partial.render(args)
	end

	# TODO this is a hack because I can't find a way to hand functions through to the page context.
	def cleanForJavascript(input, single=true, double=false)
		#result = stripHTML(input) # TODO
		result = input
		result = result.gsub('"', '') if double
		result = result.gsub("'", "") if single
		result = result.gsub(" ", "_")
		result = result.gsub("/", "")
		return result
	end
		
	def escapeForJavascript(input, single=true, double=false)
		result = input
		result = result.gsub('"', '') if double
		result = result.gsub("'", "") if single
		return result
	end
		
	def cleanForUrl(input)
		#result = stripHTML(input) # TODO
		return URI.escape(input)
	end
	
	def ==(other)
		return false if self.class != other.class
		return self.path == other.path
	end
end

class IndexPage < Page
	def <=>(right)
		return self.class <=> right.class
	end
	
	def generatePrereqs(args)
		super(args)
		
		wordcount = 0
		stories = Story.all
		stories.each do |s|
			wordcount += s.wordcount
		end
		
		@keywords['count'] = stories.size
		@keywords['wordcount'] = formatLongNumber(wordcount)
	end	
end

class YearPage < Page
	def details=(argl)
		year = argl[0]
		self.applyDestinationPattern([year, ])
		@message = 'Generating story listing for %s...' % [year, ]
		
		ynum = Integer(year)
		start = DateTime.new(ynum, 1, 1, 0, 0, 1, 0)
		stop = DateTime.new(ynum, 12, 31, 23, 59, 59, 0)

		stories = Story.publishedBetween(start, stop)
		wordcount = 0
		scount = 0
		stories.each do |s|
			wordcount += s.wordcount
			scount += 1
		end

		@keywords['year'] = year
		@keywords['stories'] = stories
		@keywords['wordcount'] = formatLongNumber(wordcount)
		@keywords['count'] = scount
	end
end

class FixedPage < Page
	def details=(argl)
		data = argl[0]
		self.applyDestinationPattern(data.page)
		@message = @message % [data.title, ]
		@keywords['pagetitle'] = data.title
		@keywords['content'] = data.content
	end
end

class SeriesPage < Page
	def details=(argl)
		series = argl[0]
		self.applyDestinationPattern([series.url(), ])
		@message = "Generating pages for series %s..." % [series.title, ]
		@keywords['series'] = series
		wordcount = 0
		series.stories.each do |s|
			wordcount += s.wordcount
		end
		@keywords['wordcount'] = formatLongNumber(wordcount)
	end
	
	def <=>(other)
		return self.class <=> other.class if self.class != other.class
		return self.keywords['series'].id <=> other.keywords['series'].id
	end
end

class PrintableSeriesPage < SeriesPage
	def details=(argl)
		series = argl[0]
		self.path = File::join($output, 'stories', series.printableurl())
		self.keywords['series'] = series
	end
end

class EPubBook < Page
	def details=(argl)
		self.message = 'Generating epub file for standalone stories...'
		self.path = File::join($output, 'stories', 'printable', 'all_stories.epub') # TODO templatable
	end

	def render
		puts @message if @message != nil
		self.generatePrereqs([])
		
		@keywords['author'] = Author.all.first.name # TODO
		
		@epub = GEPUB::Book.new('Fanfiction by '+@keywords['author']) # TODO templatable
		@epub.author = @keywords['author']
		@epub.publisher = $generator + ' ' + $version
		@epub.date = Time.now.strftime('%Y-%m-%d')
		@epub.identifier = self.path

		covertmpl = Haml::Engine.new(File.open($templates + 'epub_cover.haml').read)
		cover = @epub.add_item("coverpage.html", StringIO.new(covertmpl.render(@keywords)))
		@epub.spine << cover
		@epub.add_nav(cover, 'Table of Contents')

		i = 0
		stories = Story.standalone
		stories.each do |story|			
			i += 1
			self.addStory(story, i)
		end

		@epub.generate_epub(self.path)
	end

	def addStory(story, indexnum)
		if story.banner != nil
			banner = @epub.add_item(story.banner.idtag, File.open(story.banner.fileloc))
			@keywords['bannertag'] = story.banner.idtag
		else
			@keywords.delete('bannertag')
		end
	
		@keywords['story'] = story
	
		if story.sections.size > 1
			tmpl = Haml::Engine.new(File.open($templates + 'epub_multiseg_contents.haml').read)
			content = tmpl.render(@keywords)
			item = @epub.add_item(story.relativeurl, StringIO.new(content))
			@epub.spine << item
			@epub.add_nav(item, String(indexnum) + ". " + story.title)
	
			tmpl = Haml::Engine.new(File.open($templates + 'epub_content.haml').read)
			j = 0
			story.sections.each do |segment|
				j += 1
				@keywords['segment'] = segment
				content = tmpl.render(@keywords)
				item = @epub.add_item(segment.idtag, StringIO.new(content))
				@epub.spine << item
				@epub.add_nav(item, '&nbsp;&nbsp;&nbsp;'+String(j)+'. '+segment.title)
			end
		else
			content = @template.render(@keywords)
			item = @epub.add_item(story.relativeurl, StringIO.new(content))
			@epub.spine << item
			@epub.add_nav(item, String(indexnum) + ". " + story.title)
		end
	end
end

class EPubSeriesBook < EPubBook
	def <=>(other)
		return self.class <=> other.class if self.class != other.class
		return self.keywords['series'].id <=> other.keywords['series'].id
	end

	def details=(argl)
		series = argl[0]
		self.applyDestinationPattern([series.url(), ])
		self.keywords['series'] = series
		self.message = "    epub file for %s..." % [series.title, ]
		self.path = series.epuburl()
		self.path = File::join($output, 'stories', series.epuburl())
		wordcount = 0
		series.stories.each do |s|
			wordcount += s.wordcount
		end
		@keywords['wordcount'] = formatLongNumber(wordcount)
	end
	
	def render
		puts @message if @message != nil
		self.generatePrereqs([])

		require 'gepub'
		require 'fileutils'
		
		series = @keywords['series']
		@keywords['author'] = series.printableAuthor
		
		@epub = GEPUB::Book.new(series.title)
		@epub.author = @keywords['author']
		@epub.publisher = $generator + ' ' + $version
		@epub.date = series.numeric_date
		@epub.identifier = self.path
		
		if series.hasBanner
			bobj = series.getBanner
			banner = @epub.add_item(bobj.idtag, File.open(bobj.fileloc))
			@epub.specify_cover_image(banner)
			@keywords['bannertag'] = bobj.idtag
		end
		covertmpl = Haml::Engine.new(File.open($templates + 'epub_series_cover.haml').read)
		cover = @epub.add_item("coverpage.html", StringIO.new(covertmpl.render(@keywords)))
		@epub.spine << cover
		@epub.add_nav(cover, 'Table of Contents')
		
		i = 0
		series.storiesInOrder.each do |story|
			i += 1
			self.addStory(story, i)
		end

		@epub.generate_epub(self.path)
	end
end

class StoryPage < Page
	def details=(argl)
		story = argl[0]
		indent = argl[1]
		
		if indent
			self.message = "    %s" % [story.title, ]
		else
			self.message = "Generating pages for %s..." % [story.title, ]
		end
		
		self.applyDestinationPattern([story.url(), ])
		self.keywords['story'] = story
	end

	def ==(other)
		return false if self.class != other.class
		return self.keywords['story'].id == other.keywords['story'].id
	end

	def <=>(other)
		return self.class <=> other.class if self.class != other.class
		return self.keywords['story'].id <=> other.keywords['story'].id
	end
end

class FandomPage < Page
	def details=(argl)
		fandom = argl[0]
		@message = "Generating %s index..." % [fandom.idtag, ]
		self.applyDestinationPattern([fandom.idtag, ])
		@keywords['fandom'] = fandom
		wordcount = 0
		fandom.stories.each do |s|
			wordcount += s.wordcount
		end
		@keywords['wordcount'] = formatLongNumber(wordcount)
	end

	def ==(other)
		return false if self.class != other.class
		return self.keywords['fandom'].idtag == other.keywords['fandom'].idtag
	end

	def <=>(other)
		return self.class <=> other.class if self.class != other.class
		return self.keywords['fandom'].idtag <=> other.keywords['fandom'].idtag
	end
end

class SizedItemPage < Page
	def details=(argl)	
		kind = argl[0]
		if kind == 'tags'
			tags = Tag.allSorted
			self.setSizedItem('tags', tags)
		elsif kind == 'pairings'
			pairings = Pairing.allSorted()
			self.setSizedItem('pairings', pairings)
		end
	end

	def setSizedItem(label, items)
		self.keywords['label'] = label
		self.message = '    %s page...' % [label, ]
		
		# generate javascript, because it's hackier in the templates
		# no, really, it would be hackier there.
		jscript = ''
		taglist = {}
		items.each do |t|
			cleaned = self.cleanForJavascript(t.name)
			
			jscript += "tagdata['#{cleaned}'] = new Array();\n"
			jscript += "tagdata['#{cleaned}']['link'] = \"#{cleaned}_link\";\n"
			jscript += "tagdata['#{cleaned}']['name'] = \"#{t.name}\";\n"
			jscript += "tagdata['#{cleaned}']['contents'] = [\n";
			if label == 'tags'
				stories = Story.taggedWith(t)
			elsif label == 'pairings'
				stories = Story.findByPairing(t)
			else
				stories = []
			end
			stories.each do |s|
				jscript += "	\"#{s.idtag}\",\n"
			end
			jscript += "];\n"
			taglist[t] = stories
		end
		self.keywords['jscript'] = jscript
		
		res = self.calculateSizes(items, taglist)
		self.keywords['sizes'] = res[1]
		self.keywords[label] = res[0]
	end

	def calculateSizes(input, taglist)
		return {} if input.length == 0
		
		firstt = taglist[input[0]]
		
		max = firstt.size
		min = firstt.size
		sizes = {}
		output = []
		
		input.each do |item|
			sz = taglist[item].size
			next if sz == 0
			output << item
			sizes[item] = sz
			max = sz if (sz > max)
			min = sz if (sz < min)
		end

		range = Math.log(max) - Math.log(min)	
		kMinSize = 75
		kMaxSize = 225
		kFontRange = kMaxSize - kMinSize
		
		output.each do |item|
			next if taglist[item].size == 0
			weight = (Math.log(sizes[item]) - Math.log(min)) / range
			sizes[item] = Integer(kMinSize + weight * kFontRange)
		end
		return output, sizes
	end

	def ==(other)
		return false if self.class != other.class
		return self.keywords['label'] == other.keywords['label']
	end

	def <=>(other)
		return self.class <=> other.class if self.class != other.class
		return self.keywords['label', '']<=> other.keywords['label', '']
	end
end

class FeedPage < Page
	def ==(other)
		return self.class == other.class
	end

	def <=>(right)
		return self.class <=> right.class
	end
	
	def render
		puts self.message if self.message
		self.generatePrereqs([])
	
		site = @keywords['site']
		latest = @keywords['latest']
	
		urlstart = site.url
		
		feed = AtomFeed.new
		feed.title = site.title
		feed.subtitle = site.subtitle
		feed.addLink(urlstart + 'feeds/recent.atom', 'self')
		feed.addLink(urlstart, 'alternate')
		feed.updated = latest.first.publicationDateTime
		
		authors = {}
		
		latest.each do |s|
			entry = AtomEntry.new
			entry.title = s.title
			
			content = @template.render(s)
			entry.summary = s.summary
			entry.content = AtomContent.new(content, 'html')
			entry.updated = s.publicationDateTime
			entry.addLink(urlstart + s.url, 'alternate')
			
			s.authors.each do |a|
				if authors.has_key?(a.name)
					person = authors[a.name]
				else
					person = a.toAtomPerson()
					authors[a.name] = person
				end
				entry.authors << person
			end
			
			s.tagsSorted.each do |t|
				entry.categories << t.name
			end
	
			feed.entries << entry
		end
		
		authors.each do |a|
			feed.authors << a[1]
		end
		
		fp = File.new(@path, 'w')
		fp.puts(feed.atom)
		fp.close
	end	
end

def pageFactory(type, *args)
	page = nil

	case type
	when :story
		page = StoryPage.new('story.haml', nil, '%s', ['site', ])
	when :index
		page = IndexPage.new('index.haml', "Generating index page...", 'index.html', ['site', 'fandoms', 'datestamp', ])
	when :story_index
		page = Page.new('all.haml', '    sortable index...', 'all.html', ['site', 'fandoms', 'stories',])
	when :fandom
		page = FandomPage.new('fandom.haml', nil, 'index_%s.html', ['site', 'fandoms'])
	when :series
		page = SeriesPage.new('series.haml', nil, '%s', ['site', 'fandoms'])
	when :epub
		page = EPubSeriesBook.new('epub_single_segment.haml', nil, '%s', ['site', ])
	when :epub_book
		page = EPubBook.new('epub_single_segment.haml', nil, '%s', ['site', 'fandoms', 'stories', 'datestamp', ])
	when :printable
		page = PrintableSeriesPage.new('printable.haml', nil, '%s', ['site', ])
	when :latest
		page = Page.new('new.haml', "Generating newest-stories page...", 'new.html', ['site', 'latest', 'fandoms', ])
	when :tags
		page = SizedItemPage.new('tags.haml', nil, 'tags.html', ['site', 'stories', 'fandoms', ])
		args = ['tags',] # your sign of hack TODO
	when :pairings
		page = SizedItemPage.new('pairings.haml', nil, 'pairings.html', ['site', 'stories', 'fandoms', ])
		args = ['pairings',]
	when :feeds
		page = FeedPage.new('story_feed.haml', 'Generating atom feeds...', File::join('feeds', 'recent.atom'), ['site', 'latest',])
	when :year
		page = YearPage.new('year.haml', 'Generating story listing for %s...', 'stories_%s.html', ['site', ])
	when :static
		page = FixedPage.new('static.haml', 'Generating static page %s...', '%s.html', ['site', ])
	when :bookmarks
		page = Page.new('bookmarks.haml', 'Generating bookmarks page for Pinboard import...', 'pinboard_bookmarks.html', ['site', 'stories', ])
	else
		puts "Unknown page type: #{type}; falling back to generic"
		page = Page.new
	end
	
	page.details = args
	return page
end

def generateFandomPage(fandom)
	page = pageFactory(:fandom, fandom)
	markDirty(page)
end

def generateSeriesPages(series, regenStories=true)
	page = pageFactory(:series, series)
	markDirty(page)
	page = pageFactory(:printable, series)
	markDirty(page)
	if regenStories
		series.stories.each do |s|
			generateStoryPage(s, true)
		end
	end
end

def generateEpubPages(series)
	page = pageFactory(:epub, series)
	markDirty(page)
end

def generateStoryPage(story, indent=false)
	page = pageFactory(:story, story, indent)
	markDirty(page)
	if story.wouldBeInLatest()
		markDirty(pageFactory(:latest))
		markDirty(pageFactory(:feeds))
	end
end
		
def generateListingForYear(year)
	page = pageFactory(:year, year)
	markDirty(page)
end

def updateStaticFiles(lastmod)
	puts 'Looking for changed static files...'
	pathprefix = $input + '/static/'

	statics = Dir::glob(pathprefix + "**/*.*", File::FNM_DOTMATCH)
	statics.each do |candidate|
		next if candidate.match(/\.DS_Store$/) || candidate.match(/\.svn/)
		next if candidate.match(/\.$/) || candidate.match(/\.\.$/)
		destination = candidate.sub(pathprefix, $output+'/')
		if File.directory?(candidate)
			puts candidate
		else
			if !File.exist?(destination) || leftIsNewer(candidate, destination)
				base = File.basename(destination)
				puts "    copying %s" % [base, ]
				FileUtils.mkdir_p(File.dirname(destination))
				FileUtils.copy(candidate, destination)
				# this is definitely hacky
				if base.match(/^jquery\-.*\.js/)
					syml = $output+'/scripts/'+'jquery.js'
					if File.symlink?(syml) && File.readlink(syml) != destination
						File.unlink(syml)
						File.symlink(destination, syml)
					end
				end
			end
		end
	end
end

def generateCSS(lastmod)
	stylesheets = Dir::glob($templates + '*.sass')
	stylesheets.each do |candidate|
		destination = candidate.sub(/\.sass$/, '.css')
		destination.sub!($templates, $output+'/css/')
		if !File.exist?(destination) || leftIsNewer(candidate, destination)		
			puts "   compiling stylesheet %s" % [File.basename(candidate), ]
			data = File.read(candidate)
			engine = Sass::Engine.new(data)
			fp = File.new(destination, 'w')
			fp.puts engine.render
			fp.close
		end
	end
end

def isNewerTemplate(tmpl, lastmod)
	path = Pathname.new($templates) + tmpl
	stat = File::Stat.new(path)
	return stat.mtime.to_datetime > lastmod
end

def leftIsNewer(left, right)
	lp = Pathname.new(left)
	rp = Pathname.new(right)
	return File::Stat.new(lp).mtime > File::Stat.new(rp).mtime
end

def checkForUpdatedTemplates(lastmod, options)
	# poor man's dependencies. eventually will need work.
	dofandoms = false
	doseries = false
	doepub = options[:epub]

	markDirty(pageFactory(:index)) if isNewerTemplate('index.haml', lastmod)
	markDirty(pageFactory(:story_index)) if isNewerTemplate('all.haml', lastmod)
	markDirty(pageFactory(:latest)) if isNewerTemplate('new.haml', lastmod)
	markDirty(pageFactory(:feeds)) if isNewerTemplate('story_feed.haml', lastmod)
	markDirty(pageFactory(:pairings)) if isNewerTemplate('pairings.haml', lastmod)
	markDirty(pageFactory(:tags)) if isNewerTemplate('tags.haml', lastmod)
	
	if isNewerTemplate('story_blurb.haml', lastmod)
		markDirty(pageFactory(:latest))
		markDirty(pageFactory(:pairings))
		markDirty(pageFactory(:tags))
		dofandoms = true
		doseries = true
	end
	
	if isNewerTemplate('static.haml', lastmod)
		StaticPage.all.each do |f|
			markDirty(pageFactory(:static, f))
		end
	end

	if dofandoms || isNewerTemplate('fandom.haml', lastmod)
		Fandom.all.each do |f|
			generateFandomPage(f)
		end
	end

	if doseries || isNewerTemplate('series.haml', lastmod)
		seriesToUpdate = Series.all
		seriesToUpdate.each do |s|
			generateSeriesPages(s, false)
		end
	end

	if doepub || isNewerTemplate('epub_content.haml', lastmod) || isNewerTemplate('epub_cover.haml', lastmod)
		markDirty(pageFactory(:epub_book))
		seriesToUpdate = Series.all
		seriesToUpdate.each do |s|
			generateEpubPages(s)
		end
	end

	if isNewerTemplate('story.haml', lastmod)
		Story.all.each do |s|
			page = pageFactory(:story, s, false)
			markDirty(page)
		end
	end

	if isNewerTemplate('printable.haml', lastmod)
		Series.all.each do |s|
			page = pageFactory(:printable, s)
			markDirty(page)
		end
	end
end
