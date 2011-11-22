#-------------------------------------------------------------------------------
# fic site data models for datamapper/sqlite

require 'dm-core'
require 'dm-aggregates'
require 'dm-ar-finders'
require 'dm-migrations'

require 'datamapper-tags'

# required before we define the datamapper classes
dbname = $gConfig[:sqlite][:dbfile]
needsMigration = !File.exist?(dbname)
DataMapper.setup(:default, {
    :adapter  => 'sqlite3',
    :database => dbname,
  })

def initializeORM()
end

class Tag
	include TagMixin

	# extend the datamapper tag model with this
	def self.allSorted
		tagl = Tag.all()
		tagl.sort!
		tagl
	end
end

class Site
    include DataMapper::Resource

	property :id, Serial
	property :title, String
	property :subtitle, String
	property :url, String
	property :description, Text
	property :modified, DateTime

	def self.default
		# this tool is single-site but still has some multi-site cruft
		Site.first
	end

	def self.lastModified
		default = Site.default
		return default.modified if default != nil && default.modified != nil
		return $earliestDate
	end
	
	def loadFromYaml(input)
		self.subtitle = input.subtitle if input.subtitle != self.subtitle && (self.subtitle != input.subtitle)
		self.url = input.url if input.url != nil && (self.url != input.url)
		self.url = self.url + '/' if self.url.slice(-1,1) != '/'
		self.description = input.description if input.description != nil && (self.description != input.description)
		if self.dirty?
			if self.save
				puts "updating site #{self.title}"
				return true
			else
				self.errors.each do |e|
					puts e
				end
			end
		end
		return false
	end

	def self.findOrCreate(title)
		return Site.find_or_create(:title => title)
	end
end

class Author
	include DataMapper::Resource
	property :id, Serial
	
	property :name, String, :required => true
	property :login, String
	property :email, String, :unique => true
	property :url, Text
	
	def loadFromYaml(input)
		self.name = input.name if input.name != nil && (self.name != input.name)
		self.login = input.login if input.login != nil && (self.login != input.login)
		self.email = input.email if input.email != nil && (self.email != input.email)
		self.url = input.url if input.url != nil && (self.url != input.url)
		if self.dirty?
			if self.save
				puts "updating author #{self.name}"
				return true
			else
				self.errors.each do |e|
					puts e
				end
			end
		end
		return false
	end

	def idtag
		return makeidtag(self.name)
	end

	def self.findOrCreate(name)
		return Author.find_or_create(:name => name)
	end

	def toAtomPerson
		person = AtomPerson.new
		person.name = self.name
		person.email = self.email
		person.uri = self.url
		return person
	end
end

class Fandom
	include DataMapper::Resource

	has n, :stories, :through => Resource, :order => [ :pairing_main.asc, :title.asc ]
	has n, :series, :through => Resource, :order => [ :pairing_main.asc, :title.asc ]

	property :id, Serial
	property :idtag, String
	property :title, String
	property :description, Text
	property :default, Boolean
	
	def loadFromYaml(input)
		self.title = input.title if input.title != self.title && (self.title != input.title)
		self.description = input.description if input.description != nil && (self.description != input.description)
		self.default = input.default if input.default != nil && (self.default != input.default)
		if self.dirty?
			puts "updating fandom #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(idtag)
		idtag.downcase!
		return Fandom.find_or_create(:idtag => idtag)
	end

	def standalone
		result = Story.all(:series => nil)
		result.sort
		return result
	end
	
	def indexItems
		result = []
		self.series.each do |s|
			result << s
		end
		tmp = []
		self.stories.each do |s|
			tmp << s if (s.series == nil)
		end
		result = result | tmp
		result = result.sort_by {|item| [item.pairing_main.downcase, item.titleNoStopWords]}
		return result
	end

	def self.default
		Fandom.first(:default => true)
	end
	
	def self.allSorted
		Fandom.all
	end
end

class Pairing
	include DataMapper::Resource
	property :id, Serial

	property :name, String
	has n, :stories, :through => Resource

	def printable
		return makePairingPrintable(self.name)
	end

	def self.findOrCreate(name)
		name.downcase!
		return Pairing.find_or_create({:name => name})
	end

	def self.allSorted
		Pairing.all(:order => [:name.asc])
	end
end

class Series
	include DataMapper::Resource
	include SeriesMixin
	property :id, Serial

	property :idtag, String, :index => :unique
	property :title, String
	property :summary, String
	has n, :stories, :order => [ :series_order.asc]	
	has n, :authors, :through => Resource
	has n, :fandoms, :through => Resource
	belongs_to :banner, :required => false
	property :pairing_main, String

	property :modified, DateTime
	property :published, DateTime
	
	attr :bannerurl

	def loadFromYaml(input)
		self.title = input.title if input.title != nil && (self.title != input.title)
		self.summary = input.summary if input.summary != nil && (self.summary != input.summary)
		self.published = input.published if input.published != nil && (self.published != input.published)
		self.pairing_main = input.pairing_main if input.pairing_main != nil && (self.pairing_main != input.pairing_main)
		if input.bannerurl != nil
			b = Banner.findOrCreate(input.bannerurl)
			self.banner = b if b != self.banner
		end
		if self.dirty?
			puts "updating series #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(idtag)
		idtag.downcase!
		return Series.find_or_create(:idtag => idtag)
	end

	def storiesInOrder
		self.stories
	end

	def numeric_date
		latest = nil
		self.stories.each do |s|
			latest = s.published if latest == nil or s.published > latest
		end
		return latest.strftime('%Y-%m-%d')
	end	
end

class Story
	include DataMapper::Resource
	include StoryMixin

	property :id, Serial
	has n, :sections
	has n, :authors, :through => Resource
	has n, :fandoms, :through => Resource
	has n, :pairings, :through => Resource

	has_tags_on :tags
	
	property :source, String, :key => true
	property :title, String, :key => true
	property :awards, String
	property :commentary, String
	property :disclaimer, String
	property :notes, String
	property :rating, String
	property :summary, String
	property :warnings, String
	property :wordcount, Integer, :default => 0

	property :modified, DateTime
	property :published, DateTime

	belongs_to :series, :required => false
	property :series_order, Integer
	attr_accessor :previousInSeries
	attr_accessor :nextInSeries

	belongs_to :banner, :required => false
	attr :bannerurl
	property :pairing_main, String

	def self.standalone
		return Story.all(:series => nil).sort   
	end
	
	def self.totalCount
		Story.count
	end
	
	def self.allSorted
		return Story.all().sort
	end

	def self.taggedWith(tag)
		Story.tagged_with(tag.name)
	end

	def self.findByPairing(pairing)
		# the pairing record has this info
		pairing.stories
	end

	def self.modifiedSince(lastmod)
		Story.all(:modified.gt => lastmod)
	end
	
	def self.publishedBetween(start, stop)
		Story.all(:published.gte => start, :published.lte => stop, :order => [ :published.asc ])
	end
	
	def self.fetchRecent(count)
		Story.all(:limit => count, :order => [ :published.desc ])
	end
	
	def wouldBeInLatest
		fencepost = Story.first(:limit => 1, :offset => 10, :order => [ :published.desc ])
		return self.published > fencepost.published
	end

	# authorLink
	# authorList
	
	def publicationDateTime
		return self.published
	end
	
	def altlink
		if self.sections != nil and self.sections.length > 0
			return self.sections[0].altlink
		end
		return nil
	end

	def tagsSorted
		self.tags
	end

	def previousInSeries
		return nil if self.series == nil
		if @previousInSeries == nil
			@previousInSeries = Story.first(:series_order.lt => self.series_order, :series_id => self.series_id, :order => [ :series_order.desc ])
		end
		return @previousInSeries
	end
	
	def nextInSeries
		return nil if self.series == nil
		if @nextInSeries == nil
			@nextInSeries = Story.first(:series_order.gt => self.series_order, :series_id => self.series_id, :order => :series_order)
		end
		return @nextInSeries
	end

	def loadFromYaml(item, f, modtime, refresh)
		if !refresh && (self.modified != nil) && (modtime <= self.modified)
			return false
		end

		if (self.published == nil)
			puts "adding '#{item['title']}'"
		else
			puts "updating #{self.id}: '#{self.title}'"
		end
		
		if item['title'] == nil
			puts item['summary']
		end
		
		self.title = item['title'] if (self.title != item['title'])
		self.rating = item['rating'] if (self.rating != item['rating'])
		self.summary = rewriteLJLinks(item['summary']) if (self.summary != item['summary'])
		self.warnings = item['warnings'] if (self.warnings != item['warnings'])
		self.notes = rewriteLJLinks(item['notes']) if (self.notes != item['notes'])
		self.disclaimer = item['disclaimer'] if (self.disclaimer != item['disclaimer'])
		self.commentary = item['commentary'] if (self.commentary != item['commentary'])
		self.awards = item['awards'] if (self.awards != item['awards'])
		
		if item['bannerurl'] != nil
			b = Banner.findOrCreate(item['bannerurl'])
			self.banner = b if b != self.banner
		end
		
		if item['published'].nil?
			self.published = DateTime.now
		elsif item['published'].kind_of?(DateTime)
			self.published = item['published']
		elsif item['published'].kind_of?(Time)
			self.published = item['published'].to_datetime
		else
			self.published = DateTime.parse(item['published'])
		end
			
		self.modified = modtime
		
		self.authors << Author.findOrCreate(item['author'])
		
		self.pairing_main = item['pairing_main'] if item['pairing_main'] != nil && (self.pairing_main != item['pairing_main'])
		self.pairing_main = 'gen' if self.pairing_main == nil || self.pairing_main.length == 0
		self.pairing_main.downcase!

		if item['pairings'] != nil
			# TODO is there a more subtle way to do this?
			self.pairings do |p|
				self.pairings.delete(p)
			end
		
			item['pairings'].each do |p|
				foo = Pairing.findOrCreate(p)
				self.pairings << foo
			end			
		end
		foo = Pairing.findOrCreate(self.pairing_main)
		self.pairings << foo if !self.pairings.include?(foo)

		if item['tags']
			self.tag_list = item['tags'].join(', ')
			self.save
		end
		
		if item['fandoms'] != nil
			self.fandoms = []
			item['fandoms'].each do |f|
				fandom = Fandom.findOrCreate(f)
				self.fandoms << fandom 
			end
		else
			default = Fandom.default
			if default != nil && !self.fandoms.include?(default)
				self.fandoms << default 
			end
		end
		
		self.series_order = item['series-order'] if (item['series-order'] != self.series_order)
		if item['series-tag'] != nil
			series = Series.findOrCreate(item['series-tag'])
			if !series.stories.member?(self)
				initial = series.stories.size
				series.stories << self
				series.stories.sort
			end
			
			self.fandoms.each do |f|
				series.fandoms << f
			end
			if series.pairing_main == nil
				series.pairing_main = self.pairing_main
			end
			series.save
		end
		
		if item['parts'] != nil
			i = 0
			item['parts'].each do |part|
				if i < self.sections.size
					items = self.sections.to_a
					segment = items[i]
					segment.title = part['title']
				else
					segment = self.sections.create(:title => part['title'])
				end
				segment.summary = rewriteLJLinks(part['summary'])
				segment.content = rewriteLJLinks(part['content'])
				segment.altlink = part['altlink']
				if part['published']
					segment.published = DateTime.parse(part['published'])
				else
					segment.published = self.published
				end
				segment.modified = segment.modified
				segment.save!
				i += 1
			end
		else
			if self.sections.size > 0
				segment = self.sections.first
				segment.title = self.title
				segment.published = self.published
				segment.modified = self.modified
			else
				segment = self.sections.create(:title => self.title, :published => self.published, :modified => self.modified)
			end
			segment.summary = rewriteLJLinks(self.summary)
			segment.content = rewriteLJLinks(item['content'])
			segment.altlink = item['altlink']

			segment.save!
		end
		
		self.wordcount = self.countWords

		self.save
		return true
	end

	def self.findOrCreate(source, title)
		return Story.find_or_create({:source => source, :title => title})
	end
end

class Section
	include SectionMixin
	include DataMapper::Resource
	property :id, Serial

	belongs_to :story
	property :title, String, :required => true
	property :summary, String
	property :altlink, String
	property :content, Text

	property :modified, DateTime
	property :published, DateTime
	
end

class Banner
	include BannerMixin
	include DataMapper::Resource
	property :id, Serial

	property :url, Text
	property :width, Integer
	property :height, Integer
	property :alt, String
	property :link, String

	def loadFromYaml(input)
		self.url = input.url if input.url != self.url
		self.width = input.width if input.width != self.width
		self.height = input.height if input.height != self.height
		self.alt = input.alt if input.alt != self.alt
		self.link = input.link if input.link != self.link

		if self.dirty?
			puts "found banner #{self.alt}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(url)
		return Banner.find_or_create(:url => url)
	end
end

class StaticPage
	include DataMapper::Resource
	property :id, Serial

	property :page, String, :required => true
	property :title, String
	property :content, Text
	property :modified, DateTime

	def loadFromYaml(input)
		self.page = input.page if input.page != nil && (self.page != input.page)
		self.title = input.title if input.title != nil && (self.title != input.title)
		self.content = input.content if input.content != nil && (self.content != input.content)
		if self.dirty?
			self.modified = DateTime.now
			puts "updating page #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(page)
		return StaticPage.find_or_create(:page => page)
	end
	
	def self.modifiedSince(lastmod)
		StaticPage.all(:modified.gt => lastmod)
	end
end

DataMapper.finalize
DataMapper.auto_migrate! if needsMigration
