#!/usr/bin/env ruby

require 'rubygems'
require "bundler/setup"

require 'bluecloth'
require 'choice'
require 'date'
require 'fileutils'
require 'gepub'
require 'haml'
require 'htmlentities'
require 'pathname'
require 'pp'
require 'sass'
require 'time'
require 'uri'
require 'yaml'

$LOAD_PATH << File.join(File.dirname(__FILE__), 'lib')
require 'atom'
require 'common'
require 'renderer'

$configFile = 'config.yml'
$gConfig = []
$templates = ''

$generator = 'ficsitegen'
$version = '0.3'

#-------------------------------------------------------------------------------
# parsing input files

def handleDocument(input, f, modtime, refresh)
	if input.kind_of?({}.class)
		story = Story.findOrCreate(f, input['title'])
		return story.loadFromYaml(input, f, modtime, refresh)
	end
	if input.kind_of?(AuthorYaml)
		author = Author.findOrCreate(input.name)
		author.loadFromYaml(input)
		return false
	end
	if input.kind_of?(SeriesYaml)
		series = Series.findOrCreate(input.idtag)
		return series.loadFromYaml(input)
	end
	if input.kind_of?(SiteYaml)
		site = Site.findOrCreate(input.title)
		return site.loadFromYaml(input)
	end
	if input.kind_of?(FandomYaml)
		fandom = Fandom.findOrCreate(input.idtag)
		fandom.loadFromYaml(input)
		return false
	end
	if input.kind_of?(BannerYaml)
		banner = Banner.findOrCreate(input.url)
		banner.loadFromYaml(input) # TODO note dependency problem
		return false
	end
	if input.kind_of?(StaticPageYaml)
		item = StaticPage.findOrCreate(input.page)
		item.loadFromYaml(input)
		return false
	end

	puts "failing to handle: #{f} #{input.class}"
	return false
end

def parseAllStoryFiles(lastmod, refresh)
	dirty = false
	Dir[File.join($input, "**", "*.yaml")].each do |f|
		begin
			fp = File.open(f)
			modtime = fp.mtime.to_datetime
			YAML.load_documents(fp) do |ydoc|
				dirty |= handleDocument(ydoc, f, modtime, refresh)
			end
			fp.close
		rescue StandardError => err
			puts "Error reading #{f}"
			puts err.inspect
			next
		end
	end
	return dirty
end

$dirtyPageList = []
def markDirty(page)
	$dirtyPageList << page if !$dirtyPageList.include?(page)
end

def processDirty
	$dirtyPageList.each do |page|
		page.render
	end
end

def main(options)
	start = Time.now
	initializeORM()

	outdir = Pathname.new($output)
	FileUtils.mkdir_p(outdir)
	FileUtils.mkdir_p(outdir + 'css')
	FileUtils.mkdir_p(outdir + 'archive')
	FileUtils.mkdir_p(outdir + 'feeds')
	FileUtils.mkdir_p(outdir + 'stories')
	FileUtils.mkdir_p(outdir + 'stories' + 'printable')
	
	lastmod = Site.lastModified
	puts "Site last updated " + lastmod.strftime("%a, %d %b %Y %H:%M%p"),"\n"

	seriesToUpdate = []
	storiesToUpdate = []

	dirty = parseAllStoryFiles(lastmod, options[:parse])

	checkForUpdatedTemplates(lastmod, options)

	if options[:generate]
		seriesToUpdate = Series.all
		storiesToUpdate = Story.standalone()
		count = Story.totalCount
		if count == 1
			puts "Regenerating 1 story..." 
		else
			puts "Regenerating all %d stories..." % [count, ]
		end
	elsif dirty
		candidates = Story.modifiedSince(lastmod)
		count = 0
		candidates.each do |s|
			if s.series
				if !seriesToUpdate.include?(s.series)
					seriesToUpdate << s.series
					count += s.series.stories.size
				end
			else
				storiesToUpdate << s
				count += 1
			end
		end
	
		if count == 1
			puts "1 story was updated.\n\n"
		else
			puts "#{count} stories were updated.\n\n"
		end
	else
		puts "No stories were updated.\n\n"
	end
	
	seriesToUpdate.each do |s|
		generateSeriesPages(s)
		s.fandoms.each do |f|
			generateFandomPage(f)
		end
	end
	
	storiesToUpdate.each do |s|
		generateStoryPage(s)
		s.fandoms.each do |f|
			generateFandomPage(f)
		end
	end
	
	if options[:year] > 0
		generateListingForYear(options[:year])
	end
		
	if dirty or options[:generate] or options[:index]
		markDirty(pageFactory(:index))
		markDirty(pageFactory(:story_index))
		markDirty(pageFactory(:pairings))
		markDirty(pageFactory(:tags))
	end
	if options[:generate] or options[:feeds]
		markDirty(pageFactory(:latest))
		markDirty(pageFactory(:feeds))
	end
	
	if options[:generate]
		items = StaticPage.all
	else
		items = StaticPage.modifiedSince(lastmod)
	end
	items.each do |p|
		markDirty(pageFactory(:static, p))
	end
	
	if options[:bookmarks]
		markDirty(pageFactory(:bookmarks))
	end
	
	processDirty()
	
	# a trifle ad hoc
	updateStaticFiles(lastmod)
	generateCSS(lastmod)

	# record our update timestamp
	site = Site.default
	site.modified = Time.now
	site.save
	
	puts "Done; %d seconds elapsed." % [(Time.now - start), ]
end

#-------------------------------------------------------------------------------
# utilities

$punctuationPattern = Regexp.compile(/[:\-\.\,!\?@#\$%\^\&*\(\)\[\]\{\}"'\/\\\n\r]/)
$stopWordKiller = Regexp.compile(/^(A|The|An)\s+/)

def makePairingPrintable(pairing)
	return 'gen' if (pairing.casecmp('gen') == 0)
	tmp = pairing.gsub(/\b\w/){$&.upcase}
	tmp.sub!(/Omc$/, 'OMC')
	tmp.sub!(/Ofc$/, 'OFC')
	tmp
end

def makeidtag(input)
	coder = HTMLEntities.new
	result = coder.decode(input.downcase)
	result.gsub!(' ', '_')
	result.gsub!($punctuationPattern, '')
	return URI.escape(result)
end

$userPat = Regexp.compile(/<lj user="([^"]*)">/)
$commPat = Regexp.compile(/<lj comm="([^"]*)">/)

# TODO perhaps too specific; consider supporting LJ clone sites
def rewriteLJLinks(input)
	return nil if input == nil
	result = input.gsub($userPat, '<b><a href="http://\1.livejournal.com/">\1</a></b>')
	result.gsub!($commPat, '<b><a href="http://community.livejournal.com/\1/">\1</a></b>')
	return result
end

# Reason #234 why Ruby is not ready for prime time: 
# Time and DateTime objects are incomparable.
class Time
	def to_datetime
		seconds = sec + Rational(usec, 10**6)
		offset = Rational(utc_offset, 60 * 60 * 24)
		DateTime.new(year, month, day, hour, min, seconds, offset)
	end
end

$earliestDate = DateTime.new(2000, 1, 1, 0, 0, 1, 0)

def formatLongNumber(number)
	# This is borrowed from Rail's number helper. I would have
	# preferred a locale-aware number formatter.
	delimiter = ','
	separator = '.'
	begin
		parts = number.to_s.split('.')
		parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1#{delimiter}")
		parts.join separator
	rescue
		number
	end
end

#-------------------------------------------------------------------------------
def analyzeTags
	tags = Tag.allSorted
	singleUseTags = []
	tags.each do |tag|
		#puts "tag: #{tag.name}"
		storyl = Story.taggedWith(tag)
		count = storyl.size
		if count == 0
			puts "#{tag.name}:   no uses, pruning"
			tag.destroy
		elsif count == 1
			singleUseTags << tag.name
		else
			# puts "    #{count}"
		end	
	end
	puts "The following tags are used only once:"
	pp singleUseTags
end

def generateSimplerYaml
	puts "Generating simpler yaml files..."
	FileUtils.mkdir_p(Pathname.new('simpler'))
	Story.allSorted.each do |story|
		puts story.title
		translated = SimplerStory.new(story)
		output = File.join('simpler', story.idtag + '.yaml')
		outp =  File.new(output, 'w')
		outp.puts translated.to_yaml(:indentation => 4)
		outp.close
	end
end

#-------------------------------------------------------------------------------
# configuration file

def readConfiguration
	begin
		data = File.read($configFile)
		$gConfig = YAML.load(data)
		# Hackity hackity global hack.
		$templates = $gConfig[:site][:templates]
		$input = $gConfig[:site][:input]
		$output = $gConfig[:site][:output]
	rescue StandardError => err
		puts err
		puts "Cannot read config file #{$configFile}. Exiting."
		exit
	end
end

#-------------------------------------------------------------------------------
# command-line options

def handleOptions
	Choice.options do
		header 'Run without options to look for files modified since the last site update time.'
		header ''
		
		header 'Data storage options:'
		option :mongo do
			long '--mongo'
			desc 'Store data in mongodb via mongoid'
			default false
		end
		
		option :redis do
			long '--redis'
			desc 'Store data in redis via ohm'
			default false
		end

		option :sqlite do
			long '--sqlite'
			desc 'Store data in sqlite via datamapper [default]'
			default true
		end

		separator ''
		separator 'Parsing and page generation:'
		option :parse do
			short '-p'
			long '--parse'
			desc 'reparse all files'
			default false
		end

		option :index do
			short '-i'
			long '--index'
			desc 'regenerate all index files'
			default false
		end
		
		option :feeds do
			short '-f'
			long '--feeds'
			desc 'regenerate all feed files'
			default false
		end
		
		option :epub do
			short '-e'
			long '--epub'
			desc 'regenerate all epub files'
			default false
		end
		
		option :generate do
			short '-g'
			long '--generate'
			desc 'regenerate all html output files'
			default false
		end
		
		option :year do
			short '-y'
			long '--year=YEAR'
			desc 'generate story listing for the given year'
			cast Integer
			default 0
		end
		
		option :bookmarks do
			short '-b'
			long '--bookmarks'
			desc 'generate bookmarks file suitable for Pinboard import'
			default false
		end
		
		option :analyzetags do
			long '--tags'
			desc 'Do not parse story files, just perform tag analysis & cleanup'
			default false
		end
		
		option :simpler do
			long '--simpler'
			desc 'Do not parse story files, just write simpler yaml files for experimentation'
			default false
		end
		
		separator ''
		option :help do
			short '-h'
			long '--help'
			desc 'Show this message'
		end
		
		option :version do
			short '-v'
			long '--version'
			desc 'Show version'
			action do
				puts "#{$generator} importer tool v#{$version}"
				exit
			end
		end
	end
end

#-------------------------------------------------------------------------------
if $0 == __FILE__
	handleOptions()
	readConfiguration()

	if Choice.choices[:redis]
		puts 'Using redis for storage.'
		require 'ohm-models'
	elsif Choice.choices[:mongo]
		puts 'Using mongo for storage.'
		require 'mongoid-models'
	else
		puts "Using sqlite for storage."
		require 'datamapper-models'
	end

	if Choice.choices[:analyzetags]
		analyzeTags
	elsif Choice.choices[:simpler]
		generateSimplerYaml
	else
		main(Choice.choices)
	end
end
