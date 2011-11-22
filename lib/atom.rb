#!/usr/bin/env ruby

# Ruby classes for generating Atom 1.0 feeds

# TODO
# sorting out the usual horrible timezone issues
# XML encoding
# finish AtomSource class
# paste in license text
# more error handling

require 'Base64'
#require 'CGI'
require 'date'
require 'time'

Generator = 'AluminumOxide'
Generator_uri = 'http://www.kelpheavyweaponry.com/wiki/published/AluminumOxide'
Generator_version = "0.3"

def formatTime(secs, fmtstring='%Y-%m-%dT%H:%M:%SZ')
	# RFC 3339 by default
	if secs.class == DateTime
		return secs.strftime(fmtstring)
	else
		return Time.at(secs).gmtime.strftime(fmtstring)
	end
end

class Array
	def atom
		output = []
		self.each do |item|
			output.push(item.atom())
		end
		return output.join("\n")
	end
end

class AtomElement
	def atom
		return 'Unimplemented Atom element output'
	end
end

class AtomComplexElement < AtomElement
	attr_accessor :id # required
	attr_accessor :title # required
	attr_accessor :updated # required
	attr_accessor :author
	attr_reader :link
	attr_accessor :rights
	attr_reader :categories
	attr_accessor :authors
	
	@@linkPattern = Regexp.compile(/http:\/\/([^\/]*)\/(.*)/)
	
	def idDateFormat
		return '%Y-%m-%d'
	end
	
	def id
		generateID if @id == nil
		return @id
	end
	
	def generateID
		if @link != nil && @link.size > 0
			firstlink = @link[0]
			matches = @@linkPattern.match(firstlink.href)
		end
		if matches != nil
			domain = matches[1]
			path = matches[2]
		end
		domain = 'unknown' if domain == nil or domain.length == 0
		path = 'index' if path == nil or path.length == 0
		
		if @updated != nil
			t = @updated
		else
			t = Time.new.gmtime # this would be what they call wrong
		end
		@id = "tag:%s,%s:%s" % [ domain, formatTime(t, self.idDateFormat), path]
	end
	
	def title=(text)
		@title = AtomText.create(text)
		@title.tag = 'title'
	end
	
	def author=(name)
		self.authors << name
	end
	
	def link=(href)
		@link = LinkList.new if @link == nil
		newlink = AtomLink.new()
		newlink.href = href
	
		self.link << newlink
	end
	
	def addLink(href, rel='alternate')
		@link = LinkList.new if @link == nil
	
		newlink = AtomLink.new()
		newlink.href = href
		newlink.rel = rel
	
		self.link << newlink
	end
	
	def rights=(text)
		@rights = AtomText.create(text)
		@rights.tag = 'rights'
	end
	
	def category=(category)
		@categories = CategoryList.new if @categories == nil
		@categories << category
	end
	
	def updated=(stamp)
		if stamp.class == Time
			@updated = stamp.to_i
		else
			@updated = stamp
		end
	end
		
end

class AtomFeed < AtomComplexElement
	attr_accessor :subtitle
	attr_accessor :icon
	attr_accessor :logo
	attr_accessor :entries
	attr_accessor :generator
	
	def idDateFormat
		return '%Y'
	end

	def initialize
		@entries = EntryList.new
		@categories = CategoryList.new
		@authors = AuthorList.new
		
		@title = AtomText.new('Untitled Feed')
		@updated = DateTime.now
		
		@generator = Generator
	end
	
	def atom
		output = []
		
		output.push('<?xml version="1.0" encoding="utf-8"?>')
		output.push('<feed xmlns="http://www.w3.org/2005/Atom">')		
		
		output.push(AtomGenerator.atom)
		output.push(@title.atom)
		output.push("\t<id>#{self.id}</id>")
		output.push("\t<updated>#{formatTime(@updated)}</updated>")
		output.push(@subtitle.atom) if @subtitle
		output.push(@link.atom) if @link
		output.push(@rights.atom) if @rights
		output.push("\t<icon>#{@icon}</icon>") if @icon
		output.push("\t<logo>#{@logo}</logo>") if @logo
		
		for c in @authors
			output.push(c.atom)
		end
		
		for c in @categories
			output.push(c.atom)
		end
		
		for e in @entries
			output.push(e.atom)
		end
		
		output.push('</feed>')
		return output.join("\n") + "\n"
	end
	
	def subtitle=(text)
		@subtitle = AtomText.create(text)
		@subtitle.tag = 'subtitle'
	end
	
end

class AtomEntry < AtomComplexElement
	attr_accessor :content
	attr_accessor :summary
	attr_accessor :published
	attr_accessor :source
	
	def initialize
		@categories = CategoryList.new
		@authors = AuthorList.new
		
		@title = AtomText.new('Untitled Entry')
		@updated = DateTime.now
	end
	
	def atom
		output = []		
		output.push('<entry>')		
		
		output.push(@title.atom)
		output.push("\t<id>#{self.id}</id>")
		output.push("\t<updated>#{formatTime(@updated)}</updated>")

		output.push(@author.atom) if @author
		output.push(@link.atom) if @link
		output.push(@summary.atom) if @summary
		output.push("\t<published>#{formatTime(@published)}</published>") if @published
		output.push(@rights.atom) if @rights

		for c in @authors
			output.push(c.atom)
		end
		
		for c in @categories
			output.push(c.atom)
		end
		
		output.push(@content.atom) if @content

		output.push('</entry>')
		return output.join("\n")
	end
	
	def content=(text)
		if (text.class == AtomContent) || (text.class == AtomText)
			@content = text
		else
			@content = AtomContent.new(text.to_s)
		end
		@content.tag = 'content'
	end
	
	def summary=(text)
		@summary = AtomText.create(text)
		@summary.tag = 'summary'
	end
end

class AtomCategory < AtomElement
	attr_accessor :term
	attr_accessor :scheme
	attr_accessor :label
	
	def atom
		output = "\t<category term=\"#{@term}\""
		output += " scheme=\"#{@scheme}\"" if @scheme
		output += " label=\"#{@label}\"" if @label
		output += ' />'
		return output
	end
end

class AtomLink < AtomElement
	attr_accessor :href # required
	attr_accessor :rel
	attr_accessor :type
	attr_accessor :hreflang
	attr_accessor :title
	attr_accessor :length
	
	@@relations = ['alternate', 'enclosure', 'related', 'self', 'via']
	def initialize
		@rel = 'alternate'
	end
	
	def atom
		output = "\t<link href=\"#{@href}\""
		output += " rel=\"#{@rel}\"" if @rel
		output += " type=\"#{@type}\"" if @type
		output += " hreflang=\"#{@hreflang}\"" if @hreflang
		output += " title=\"#{@title}\"" if @title
		output += " length=\"#{@length}\"" if @length
		output += ' />'
		return output
	end
	
	def rel=(type)
		if @@relations.include?(type)
			@rel = type
		end
	end
end

class AtomPerson < AtomElement
	attr_accessor :name # required
	attr_accessor :uri
	attr_accessor :email
	attr_accessor :tag
	
	def initialize()
		super()
		self.tag = 'author'
	end
	
	def atom
		output = []
		output.push("\t<#{@tag}>")
		output.push("\t\t<name>#{@name}</name>")
		output.push("\t\t<uri>#{@uri}</uri>") if @uri
		output.push("\t\t<email>#{@email}</email>") if @email
		output.push("\t</#{@tag}>")
		return output.join("\n")
	end
	
	def AtomPerson.create(name)
		if name.class == AtomPerson
			return name
		else
			p = AtomPerson.new
			p.name = name.to_s
			return p
		end
	end
end

class AtomText < AtomElement
	attr_accessor :type
	attr_accessor :content
	attr_accessor :tag
	
	@@types = ['html', 'xhtml', 'text']
	
	def initialize(text, type=nil)
		if type == 'html' or type == 'text/html'
			@type = 'html'
			@content = CGI::escapeHTML(text)
		elsif type == 'xhtml'
			@type = 'xhtml'
			@content = '<div xmlns="http://www.w3.org/1999/xhtml">' + text + '</div>'
		else
			@type = 'text'
			@content = text
		end
	end
	
	def atom
		return "\t<#{tag} type=\"#{@type}\">#{@content}</#{tag}>"
	end
	
	def AtomText.types
		return @@types
	end

	def AtomText.create(text)
		if text.class == String
			return AtomText.new(text)
		elsif text.class == AtomText
			return text
		else
			begin
				return AtomText.new(text.to_s)
			rescue
				return AtomText.new('ERROR')
			end
		end
	end
end

class AtomContent < AtomText
	attr_accessor :src
	
	def initialize(text, type='text')
		if AtomText.types.include?(type) || (type.index('text') == 0)
			super(text, type)
		else
			@type = type
			@content = Base64.encode64(text)
		end
	end
	
	def atom
		return super if (@src == nil) or (@src.length == 0)
		
		output = "\t<content src=\"#{@src}\""
		output += " type=\"#{@type}\"" if @type != nil
		output += "></content>"
		return output
	end
end

class AtomGenerator < AtomElement
	attr_accessor :uri
	attr_accessor :version
	attr_accessor :name
	
	def AtomGenerator.atom
		"\t<generator uri=\"#{Generator_uri}\" version=\"#{Generator_version}\">\n\t\t#{Generator}\n\t</generator>"
	end
	
	def atom
		"\t<generator uri=\"#{@uri}\" version=\"#{@version}\">\n\t\t#{@name}\n\t</generator>"
	end
end

class AtomSource < AtomFeed
	
	def atom
		output = []
		
		output.push('<source>')		
		output.push(@generator.atom) if @generator
		output.push(@title.atom)
		output.push("\t<id>#{self.id}</id>")
		output.push("\t<updated>#{formatTime(@updated)}</updated>")
		output.push(@subtitle.atom) if @subtitle
		output.push(@link.atom) if @link
		output.push(@author.atom) if @author
		output.push(@rights.atom) if @rights
		output.push("\t<icon>#{@icon}</icon>") if @icon
		output.push("\t<logo>#{@logo}</logo>") if @logo
		
		for c in @authors
			output.push(c.atom)
		end
		
		for c in @categories
			output.push(c.atom)
		end
		
		output.push('</source>')
		return output.join("\n") + "\n"
	end

	def fromFeed(feed)
		# TODO
	end
	
	def entries
		[]
	end
end

class AuthorList < Array
	def << person
		person = AtomPerson.create(person)
		for c in self
			return if c.name == person.name
		end
		self.push(person) if !self.include?(person)
	end
end

class LinkList < Array
	def << text
		if text.class == String
			link = AtomLink.new()
			link.href = text
		else
			link = text
		end
		self.push(link) if !self.include?(link)
	end
end

class EntryList < Array
	def << entry
		self.push(entry) if !self.include?(entry)
	end
end

class CategoryList < Array
	def << category
		if category.class == String
			c = AtomCategory.new
			c.term = category
			category = c
		end
		for c in self
			return if c.term == category.term
		end
		self.push(category)
	end

end

