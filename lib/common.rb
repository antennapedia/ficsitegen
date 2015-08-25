#--------------------------------------------------------------------
# Yaml classes. These are required because the various ORMs each have
# incompatible yaml serializations. Specifically, ohm nests object
# attributes inside '_attributes'. Mongoid nests inside 'attributes'.
# Datamapper doesn't nest at all.
#
# I do not want to get involved in overriding yaml serialization for the
# classes. I might change my mind about that.

class SiteYaml
	attr_accessor :title
	attr_accessor :subtitle
	attr_accessor :url
	attr_accessor :description
end

class AuthorYaml
	attr_accessor :name
	attr_accessor :login
	attr_accessor :email
	attr_accessor :url
end

class FandomYaml
	attr_accessor :idtag
	attr_accessor :title
	attr_accessor :description
	attr_accessor :default
end

class SeriesYaml
	attr_accessor :idtag
	attr_accessor :title
	attr_accessor :pairing_main
	attr_accessor :summary
	attr_accessor :published
	attr_accessor :bannerurl
end

class BannerYaml
	attr_accessor :url
	attr_accessor :width
	attr_accessor :height
	attr_accessor :alt
	attr_accessor :link
end

class StaticPageYaml
    attr_accessor :page
    attr_accessor :title
    attr_accessor :content
end

#--------------------------------------------------------------------
# Code common to all versions of the object models. I wish there were
# cleaner way to do this, but some of the ORMs use inclusion and some
# use inheritance.

module TagMixin
	# examples: c:fred, c:wilma, c:woobie!fred, f:flintstones, hurt/comfort
	# @category: anything before the : in tag text
	# @text: anything after the :
	# @decorator: anything before a !
	# @sorttext: tag text with decorator removed, so hurt!fred sorts with fred

	def splitName
		@text = self.name
		@decorator = ''
		if self.name.include?(':')
			@cat, @text = self.name.split(':')
		end
		@sorttext = @text
		if @text.include?('!')
			@decorator, @sorttext = @text.split('!')
		end
		if @cat
			@sorttext = @cat + ':' + @sorttext
		end
	end

	def category
		self.splitName if @text.nil?
		@cat
	end

	def hasCategory
		self.splitName if @text.nil?
		!@cat.nil?
	end

	def text
		self.splitName if @text.nil?
		@text
	end

	def decorator
		self.splitName if @text.nil?
		@decorator
	end

	def sorttext
		self.splitName if @text.nil?
		@sorttext
	end

	def <=>(other)
		if self.class == other.class
			if self.hasCategory != other.hasCategory
				return -1 if self.hasCategory
				return 1
			end
			if self.sorttext == other.sorttext
				return self.decorator <=> other.decorator
			else
				return self.sorttext <=> other.sorttext
			end
		else
			return self.name <=> other
		end
	end
end

module SeriesMixin
	def <=>(right)
		return self.title <=> right.title
	end

	def titleNoStopWords
		result = self.title
		result = result.gsub($stopWordKiller, '')
		return result
	end

	def url(absolute=true, includeAuthor = false)
		result = ''
		result = 'stories/' if absolute
		result += self.relativeurl(includeAuthor)
		return result
	end

	def relativeurl(includeAuthor = false)
		if 'gen' == self.pairing_main.downcase
			pairtag = 'gen'
		else
			peeps = self.pairing_main.downcase.split('/')
			pairtag = ''
			peeps.each do |p|
				pairtag << p[0]
			end
		end
		return pairtag + '_series_' + self.idtag + '.html'
	end

	def printableurl(includeAuthor = false)
		result = self.relativeurl(includeAuthor)
		return File::join('printable', result)
	end

	def epuburl(includeAuthor = false)
		result = self.printableurl(includeAuthor)
		return result.sub('html', 'epub')
	end

	def printablePairing
		return makePairingPrintable(self.pairing_main)
	end

	def hasBanner
		return (self.banner != nil) ||
				((self.stories.size > 0) && (self.stories.first.banner != nil))
	end

	def getBanner
		return self.banner if self.banner != nil
		return nil if self.stories.size == 0
		return self.stories.first.banner if self.stories.first.banner != nil
	end

	def taglist
		tagl = []
		self.stories.each do |s|
			tagl = tagl | s.tags.map {|t| t.name}
		end
		tagl.sort!
		return tagl.join(', ')
	end

	def printableAuthor
		alist = []
		self.stories.each do |s|
			alist = alist | s.authors.map {|a| a.name}
		end
		return alist.uniq.join(', ')
	end

	def <=>(other)
		if (self.pairing_main != nil) && (other.pairing_main != nil) & (self.pairing_main != other.pairing_main)
			return self.pairing_main <=> other.pairing_main
		end
		return self.titleNoStopWords <=> other.titleNoStopWords
	end
end

module StoryMixin
	def titleNoStopWords
		result = self.title.gsub($stopWordKiller, '')
		return result
	end

	def printablePairing
		return makePairingPrintable(self.pairing_main)
	end

	def idtag(includeAuthor = false)
		result = ''
		if includeAuthor
			self.authors.each do |a|
				result += a.idtag
			end
		else
			if 'gen' == self.pairing_main.downcase
				pairtag = 'gen'
			else
				peeps = self.pairing_main.downcase.split('/')
				pairtag = ''
				peeps.each do |p|
					pairtag << p[0]
				end
			end
			result = pairtag
		end

		if self.series != nil
			result = result + '_' + makeidtag(self.series.idtag)
		end
		if self.title == nil || self.title.length == 0
			return result + '_' + self.id
		end
		return result + '_' + makeidtag(self.titleNoStopWords())
	end

	def url(absolute=true, includeAuthor=false)
		result = ''
		result = 'stories/' if absolute
		result = result + self.relativeurl(includeAuthor)
		return result
	end

	def relativeurl(includeAuthor = false)
		return self.idtag(includeAuthor) + '.html'
	end

	def long_date
		return self.publicationDateTime.strftime('%B %d %Y')
	end

	def numeric_date
		return self.publicationDateTime.strftime('%Y-%m-%d')
	end

	def short_date
		return self.publicationDateTime.strftime('%B %Y')
	end

	def countWords
		return 0 if self.sections == nil
		result = 0
		self.sections.each do |p|
			result += p.content.split.size
		end
		return result
	end

	def wordcountFormatted
		return formatLongNumber(self.wordcount)
	end

	def taglist
		l = self.tagsSorted.map {|t| t.name}
		return l.join(', ')
	end

	def getBanner
		return self.banner if self.banner != nil
		return self.series.banner if self.series != nil
		return nil
	end

	def emitRating
		if self.rating.downcase == 'general'
			return 'General audiences'
		elsif self.rating.downcase == 'mature'
			return 'Mature'
		elsif self.rating.downcase == 'adult'
			return 'Adult'
		end
		return rating
	end

	# As suitable for use in an external bookmarking site.
	def emitCategorizedTags
		tags = []
		self.authors.each do |a|
			tags << "author:#{a.name}"
		end
		self.fandoms.each do |f|
			tags << "fandom:#{f.idtag}"
		end
		self.pairings.each do |p|
			tags << "pairing:#{p.name}"
		end
		self.tags.each do |t|
			if !t.category.nil? && t.category.start_with?('c')
				tags << "character:#{t.text}"
			elsif !t.category.nil? && t.category.start_with?('f')
				tags << "fandom:#{t.text}"
			else
				tags << "tag:#{t.name}"
			end
		end
		if self.wordcount <= 100
			tags << "length:drabble"
		elsif self.wordcount <= 1000
			tags << "length:<1K"
		elsif self.wordcount <= 7500
			tags << "length:<7.5K"
		elsif self.wordcount <= 17500
			tags << "length:<17.5K"
		elsif self.wordcount <= 40000
			tags << "length:<40K"
		else
			tags << "length:novel"
		end
		tags << "rating:#{self.rating.downcase}"
		tags << "fanfic"
		tags.sort.join(',')
	end

	def emitSimplerTags
		tags = []
		self.fandoms.each do |f|
			tags << "fandom:#{f.idtag}"
		end
		self.pairings.each do |p|
			tags << "pairing:#{p.name}"
		end
		self.tags.each do |t|
			if !t.category.nil? && t.category.start_with?('c')
				tags << "character:#{t.text}"
			elsif !t.category.nil? && t.category.start_with?('f')
				tags << "fandom:#{t.text}"
			else
				tags << "#{t.name}"
			end
		end
		if self.wordcount <= 100
			tags << "length:drabble"
		elsif self.wordcount <= 1000
			tags << "length:<1K"
		elsif self.wordcount <= 7500
			tags << "length:<7.5K"
		elsif self.wordcount <= 17500
			tags << "length:<17.5K"
		elsif self.wordcount <= 40000
			tags << "length:<40K"
		else
			tags << "length:novel"
		end
		tags << "rating:#{self.rating.downcase}"
		tags << "fiction"
		tags.sort.join(',')
	end

	def <=>(other)
		if self.class == other.class
			if (self.series != nil) && (self.series == other.series) &&
					(self.series_order != 0) && (self.series_order != other.series_order)
				return (self.series_order <=> other.series_order)
			end
		end
		return self.pairing_main <=> other.pairing_main if (self.pairing_main != other.pairing_main)
		return self.titleNoStopWords <=> other.titleNoStopWords
	end
end

module SectionMixin
	def formattedContent
		return 'EMPTY' if self.content == nil
		BlueCloth::new(self.content).to_html
	end

	def idtag
		return makeidtag(self.title)
	end
end

module BannerMixin
	def getTag
		result = "<img src=\"#{self.url}\" "
		result = result + "width=\"#{self.width}\", height=\"#{self.height}\" "
		if self.alt
			result = result + "alt=\"#{self.alt}\" title=\"#{self.alt}\""
		end
		result = result + ' />'
		if self.link
			result = "<a href=\"#{self.link}\">#{result}</a>"
		end
		return result
	end

	def idtag
		pieces = URI.split(self.url)
		return File.basename(pieces[5])
	end

	def fileloc
		pieces = URI.split(self.url)
		return File.join($input, 'static', pieces[5])
	end

	def cssPath
		pieces = URI.split(self.url)
		return File.join('..', pieces[5])
	end
end

## experiment in progress
class SimplerStory
	attr_accessor :owner
	attr_accessor :created
	attr_accessor :modified
	attr_accessor :title
	attr_accessor :body
	attr_accessor :icon
	attr_accessor :tags
	attr_accessor :version

	def self.template
		if @template.nil?
			@template = Haml::Engine.new(File.open($templates + 'simplerYamlBody.haml').read, options = { :format => :html5, :ugly => false })
		end
		@template
	end

	def initialize(story)
		self.version = 0
		self.icon = ''

		self.owner = story.authors.first.name
		self.created = story.published
		self.modified = story.modified
		self.title = story.title
		self.tags = story.emitSimplerTags

		opts = {}
		opts['story'] = story
		self.body = SimplerStory.template.render(opts)
	end
end

class KirjeSeries
	attr_accessor :struct

	def initialize(series)

		self.struct = Hash.new
		self.struct['version'] = 0
		self.struct['idtag'] = series.idtag
		if series.authors.first.nil?
			self.struct['owner'] = 'antennapedia'
		else
			self.struct['owner'] = series.authors.first.name
		end
		self.struct['created'] = series.modifiedLast
		self.struct['modified'] = series.modifiedLast
		self.struct['is_published'] = true
		self.struct['title'] = series.title
		self.struct['summary'] = series.summary

		self.struct['stories'] = []
		series.storiesInOrder.each do |story|
			self.struct['stories'] << story.idtag
		end

		if series.hasBanner
			b = series.getBanner
			self.struct['banner'] = b.url
		end
	end
end

class KirjeStory
	attr_accessor :struct

	@@sherlockchars = ['holmes', 'watson']
	@@whochars = ['jackie tyler', 'ninth doctor', 'rose', 'second doctor', 'zoe heriot', 'twelfth doctor', 'clara oswald', 'danny pink', 'missy', 'ace mcshane']
	@@thickkchars = [ 'malcolm tucker', 'jamie macdonald' ]
	@@hourchars = [ 'randall brown', 'lix storm' ]
	@@removechars = ['apollo', 'artemis']
	@@btvstags = [
		'core-four',
		'council',
		'episode:band-candy',
		'episode:becoming',
		'episode:dark-age',
		'episode:gift',
		'episode:grave',
		'episode:helpless',
		'episode:tabula-rasa',
		'episode:wish',
		'eyghon',
		'first-slayer',
		'fray',
		'melaka',
		'scoobies',
		'slayers',
		'watchers',
		'au:wishverse', 'wishverse'
	]

	def self.template
		if @template.nil?
			@template = Haml::Engine.new(File.open($templates + 'kirjeYamlBody.haml').read, options = { :format => :html5, :ugly => false })
		end
		@template
	end

	def initialize(story)
		self.struct = Hash.new

		self.struct['idtag'] = story.idtag
		self.struct['version'] = 0
		self.struct['owner'] = story.authors.first.name
		self.struct['created'] = story.published
		self.struct['modified'] = story.modified
		self.struct['published'] = story.published
		self.struct['is_published'] = true
		self.struct['authors'] = []
		story.authors.each do |a|
			self.struct['authors'] << a.name
		end

		self.struct['series'] = story.series.idtag if !story.series.nil?
		self.struct['title'] = story.title
		self.struct['notes'] = story.notes
		self.struct['summary'] = story.summary

		self.struct['pairing'] = story.pairing_main
		self.struct['pairings_secondary'] = {}

		self.struct['characters'] = {}
		self.struct['pairings_secondary']
		self.struct['fandom'] = story.fandoms.first.idtag
		self.struct['fandoms_additional'] = []
		story.fandoms.each do |f|
			self.struct['fandoms_additional'] << f.idtag if self.struct['fandom'] != f.idtag
			self.struct['characters'][f.idtag] = []
			self.struct['pairings_secondary'][f.idtag] = []
		end

		story.pairings.each do |p|
			if self.struct['pairing'] != p.name
				self.struct['pairings_secondary'][story.fandoms.first.idtag] << p.name
			end
		end

		self.struct['tags'] = []
		story.tags.each do |t|
			if !t.category.nil? && t.category.start_with?('c')
				if t.decorator.length > 0
					self.struct['tags'] << story.fandoms.first.idtag + ':' + t.text
				else
					next if @@removechars.include?(t.text)
					if @@whochars.include?(t.text)
						self.struct['characters']['doctor_who'] << t.text
					elsif @@sherlockchars.include?(t.text)
						self.struct['characters']['sherlock_holmes'] << t.text
					elsif @@thickkchars.include?(t.text)
						self.struct['characters']['the_thick_of_it'] << t.text
					elsif @@hourchars.include?(t.text)
						self.struct['characters']['the_hour'] << t.text
					elsif self.struct['characters']['btvs']
						self.struct['characters']['btvs'] << t.text
					else
						puts "whomp whomp #{t.text}"
					end
				end
			elsif !t.category.nil? && t.category.start_with?('f')
				self.struct['fandoms_additional'] << t.text
			elsif @@btvstags.include?(t.name)
				self.struct['tags'] << 'btvs:' + t.name
			else
				self.struct['tags'] << t.name
			end
		end

		case story.rating
		when 'adult'
			self.struct['rating'] = 3
		when 'mature'
			self.struct['rating'] = 2
		when 'general'
			self.struct['rating'] = 1
		else
			self.struct['rating'] = 2
		end

		# warnings TODO

		opts = {}
		opts['story'] = story
		self.struct['content'] = KirjeStory.template.render(opts)
	end
end
