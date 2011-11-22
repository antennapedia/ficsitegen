#-------------------------------------------------------------------------------
# mongoid data models

require 'mongoid'

Mongoid.configure do |config|
	config.master = Mongo::Connection.new($gConfig[:mongo][:host]).db($gConfig[:mongo][:db])
end
Mongoid.logger = Logger.new($stdout)

$version = '0.2 monogoid'

def initializeORM()
	# nothing to do for mongoid
end

class Tag 
	include Mongoid::Document
	include TagMixin
	
	field :name, type: String
	has_and_belongs_to_many :stories
	
	def self.findOrCreate(name)
		name.downcase!
		return Tag.find_or_initialize_by(name: name)
	end

	def self.allSorted
		ids = Tag.all()
		tagl = ids.map{|t| t}.compact
		tagl.sort!
		tagl
	end
end

class Site
	include Mongoid::Document

	field :title, type: String
	field :subtitle, type: String
	field :url, type: String
	field :description, type: String
	field :modified, type: Time

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
		if input.url
			input.url = input.url + '/' if input.url.slice(-1,1) != '/'
			input.url.strip!
			self.url = input.url if self.url != input.url
		end
		self.description = input.description if input.description != nil && (self.description != input.description)
		if self.changed?
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
		return Site.find_or_initialize_by(title: title)
	end
end

class Author
	include Mongoid::Document

	field :name, type: String
	field :login, type: String
	field :email, type: String # todo, required, unique
	field :url, type: String
	has_many :stories
	has_many :series

	def loadFromYaml(input)
		self.name = input.name if input.name != nil && (self.name != input.name)
		self.login = input.login if input.login != nil && (self.login != input.login)
		self.email = input.email if input.email != nil && (self.email != input.email)
		if self.changed?
			if self.save
				puts "updating author #{self.name}"
				return true
			end
		end
		return false
	end

	def idtag
		return makeidtag(self.name)
	end

	def self.findOrCreate(name)
		return Author.find_or_initialize_by(name: name)
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
	include Mongoid::Document

	field :idtag, type: String, :required => true, :unique => true
	field :title, type: String, :required => true
	field :default, type: Boolean, :required => false
	field :description, type: String
	has_and_belongs_to_many :stories
	has_and_belongs_to_many :series

	def loadFromYaml(input)
		self.title = input.title if input.title != nil && (self.title != input.title)
		self.description = input.description if input.description != nil && (self.description != input.description)
		self.default = input.default if (input.default != self.default)
		if self.changed?
			puts "updating fandom #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(idtag)
		idtag.downcase!
		return Fandom.find_or_initialize_by(idtag: idtag)
	end

	def standalone
		result = self.stories.where(series: nil)
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
		Fandom.first(conditions: { default: true })
	end

	def self.allSorted
		Fandom.all.sort_by{ |f| f.idtag }
	end
end

class Pairing
	include Mongoid::Document

	field :name, type: String, :required => true
	has_many :stories

	def printable
		return makePairingPrintable(self.name)
	end

	def self.findOrCreate(name)
		name.downcase!
		return Pairing.find_or_initialize_by(name: name)
	end
	
	def self.allSorted
		Pairing.all(sort: [[ :name, :asc ]])
	end
end

class Series
	include Mongoid::Document
	include SeriesMixin

	field :idtag, type: String, :required => true
	field :title, type: String, :required => true
	field :summary, type: String
	belongs_to :banner
	
	has_and_belongs_to_many :authors
	has_and_belongs_to_many :fandoms
	has_many :stories

	field :pairing_main, type: String	
	field :modified, type: Time
	field :published, type: Time
	attr_accessor :bannerurl

	def loadFromYaml(input)
		self.title = input.title if input.title != nil && (self.title != input.title)
		self.summary = input.summary if input.summary != nil && (self.summary != input.summary)
		self.published = input.published if input.published != nil && (self.published != input.published)
		self.pairing_main = input.pairing_main if input.pairing_main != nil && (self.pairing_main != input.pairing_main)
		if input.bannerurl != nil
			b = Banner.findOrCreate(input.bannerurl)
			self.banner = b if b != self.banner
		end
		if self.changed?
			puts "updating series #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(idtag)
		idtag.downcase!
		return Series.find_or_initialize_by(idtag: idtag)
	end
	
	def storiesInOrder
		self.stories.sort_by { |s| s.series_order }
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
	include Mongoid::Document
	include StoryMixin

	embeds_many :sections
	has_and_belongs_to_many :authors
	has_and_belongs_to_many :fandoms
	field :pairing_ids, type: Array, :typecast => 'ObjectId', :required => false 
	has_and_belongs_to_many :pairings
	field :pairing_main, type: String

	has_and_belongs_to_many :tags

	field :source, type: String#, :key => true
	field :title, type: String#, :key => true
	field :awards, type: String
	field :commentary, type: String
	field :disclaimer, type: String
	field :notes, type: String
	field :rating, type: String
	field :summary, type: String
	field :warnings, type: String
	field :wordcount, type: Integer, :default => 0
	
	field :modified, type: Time
	field :published, type: Time

	belongs_to :series
	field :series_order, type: Integer
	attr_accessor :previousInSeries
	attr_accessor :nextInSeries

	belongs_to :banner
	attr :bannerurl

	def self.standalone
		return Story.where(:series => nil).sort   
	end
	
	def self.totalCount
		Story.count
	end
	
	def self.allSorted
		stories = Story.all()
		stories.sort!
		return stories
	end

	def self.taggedWith(tag)
		tag.stories
	end

	def self.findByPairing(pairing)
		# the pairing record has this info
		pairing.stories
	end

	def self.modifiedSince(lastmod)
		Story.where(:modified.gt => lastmod)
	end
	
	def self.publishedBetween(start, stop)
		Story.where(:published.gte => start).where(:published.lte => stop).asc(:published)
	end
	
	def self.fetchRecent(count)
		Story.all(sort: [[ :published, :desc ]]).limit(count)
	end
	
	def wouldBeInLatest
		#fencepost = Story.first(:limit => 1, :offset => 10, :order => [ :published.desc ])
		possibilities = Story.all(sort: [[ :published, :desc ]]).skip(10).limit(1)
		fencepost = possibilities.last
		return self.published > fencepost.published
	end
	
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
		self.tags.sort_by { |t| t.name }
	end
	
	def previousInSeries
		return nil if self.series == nil
		if @previousInSeries == nil
			@previousInSeries = Story.where(:series_order.lt => self.series_order).where(:series_id => self.series_id).desc(:series_order).first
		end
		return @previousInSeries
	end
	
	def nextInSeries
		return nil if self.series == nil
		if @nextInSeries == nil
			@nextInSeries = Story.where(:series_order.gt => self.series_order).where(:series_id => self.series_id).asc(:series_order).first
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
		self.save
		
		if item['bannerurl'] != nil
			b = Banner.findOrCreate(item['bannerurl'])
			self.banner = b if b != self.banner
			self.save
		end
		
		if item['published'] != nil
			self.published = item['published']
		else
			self.published = DateTime.now
		end
		self.modified = modtime
		
		self.authors << Author.findOrCreate(item['author'])
		
		self.pairing_main = item['pairing_main'] if item['pairing_main'] != nil && (self.pairing_main != item['pairing_main'])
		self.pairing_main = 'gen' if self.pairing_main == nil || self.pairing_main.length == 0
		self.pairing_main.downcase!

		if item['pairings']
			self.pairings = []
			item['pairings'].each do |p|
				foo = Pairing.findOrCreate(p)
				self.pairings << foo
			end			
		end
		foo = Pairing.findOrCreate(self.pairing_main)
		self.pairings << foo if !self.pairings || !self.pairings.include?(foo)

		if item['tags']
			self.tags = []
			item['tags'].each do |p|
				tag = Tag.findOrCreate(p)
				self.tags << tag
				tag.stories << self
				tag.save
			end			
			self.save
		end
		
		if item['fandoms'] != nil
			self.fandoms = []
			item['fandoms'].each do |f|
				fandom = Fandom.findOrCreate(f)
				self.fandoms << fandom 
			end
			self.save
		else
			default = Fandom.default
			if default != nil && !self.fandoms.include?(default)
				self.fandoms << default 
				self.save
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
					items = self.sections
					segment = items[i]
					segment.title = part['title']
				else
					segment = self.sections.create(:title => part['title'])
				end
				segment.summary = rewriteLJLinks(part['summary'])
				segment.content = rewriteLJLinks(part['content'])
				segment.altlink = part['altlink']
				if part['published']
					segment.published = part['published']
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

		if self.save
			return true
		else
			self.errors.each do |e|
				puts e
			end
		end
		return false
	end

	def self.findOrCreate(source, title)
		return Story.find_or_initialize_by(source: source, title: title)
	end
end

class Section
	include Mongoid::Document
	include SectionMixin

	embedded_in :story
	field :title, type: String, :required => true
	field :summary, type: String
	field :altlink, type: String
	field :content, type: String

	field :modified, type: Time
	field :published, type: Time

end

class Banner
	include Mongoid::Document
	include BannerMixin

	field :url, type: String
	field :width, type: Integer
	field :height, type: Integer
	field :alt, type: String
	field :link, type: String
	
	def loadFromYaml(input)
		self.url = input.url if input.url != self.url
		self.width = input.width if input.width != self.width
		self.height = input.height if input.height != self.height
		self.alt = input.alt if input.alt != self.alt
		self.link = input.link if input.link != self.link

		if self.changed?
			puts "found banner #{self.alt}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(url)
		return Banner.find_or_initialize_by(url: url)
	end
end

class StaticPage
	include Mongoid::Document

	field :page, type: String, :required => true
	field :title, type: String
	field :content, type: String
	field :modified, type: DateTime

	def loadFromYaml(input)
		self.page = input.page if input.page != nil && (self.page != input.page)
		self.title = input.title if input.title != nil && (self.title != input.title)
		self.content = input.content if input.content != nil && (self.content != input.content)
		if self.changed?
			self.modified = DateTime.now
			puts "updating page #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(page)
		return StaticPage.find_or_initialize_by(page: page)
	end
	
	def self.modifiedSince(lastmod)
		StaticPage.where(:modified.gt => lastmod)
	end
end
