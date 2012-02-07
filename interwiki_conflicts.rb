# coding: utf-8
require 'sunflower'
require 'launchy'
require 'parallel_each'

require 'pp'


class InterwikiConflictSolver
	attr_accessor :all, :groups, :summary
	def initialize
		@sf = {}
		
		@all = []
		@groups = {}
		
		@linksfrom = {}
		@linksto = {}
		
		@summary = @summary_base = ''
	end
	
	# Creates a Sunflower with customized settings and returns it; keeps a cache.
	def get_sf wiki
		if !@sf[wiki]
			@sf[wiki] = Sunflower.new wiki+'.wikipedia.org'
		
			@sf[wiki].warnings = false
			@sf[wiki].summary = @summary
		end
		
		return @sf[wiki]
	end
	
	def gather_from wiki, article, modify_group_names=true
		start_pair = [wiki, article]
		if @all.include? start_pair
			puts "skipping #{start_pair.join ':'} - already reached"
			return
		end
		
		results = []
		results << [wiki, article]
		
		
		s = get_sf wiki
		res = s.API action:'query', prop:'langlinks', lllimit:500, titles:article
		
		iwlinks = (res['query']['pages'].first['langlinks']||[]).map{|hsh| [ hsh['lang'], hsh['*'] ] }
		
		results += iwlinks
		queue = iwlinks.dup
		
		i = 1
		while now = queue.shift
			wiki, article = *now
			puts "#{wiki.ljust 8} #{queue.length} left"
			
			s = get_sf wiki
			res = s.API action:'query', prop:'langlinks', lllimit:500, titles:article
			iwlinks = (res['query']['pages'].first['langlinks'] || []).map{|hsh| [ hsh['lang'], hsh['*'] ] }
			
			iwlinks.each do |pair|
				@linksto[pair] ||= []
				@linksto[pair] << now
			end
			
			@linksfrom[now] ||= []
			@linksfrom[now] += iwlinks
			
			iwlinks.each do |pair|
				unless results.include? pair
					results << pair
					queue << pair
				end
			end
		end
		
		results = (follow_redirects results).uniq
		@all += results
		@all.uniq!
		@all.sort!
		
		results.each do |pair|
			if @groups[pair]
				@groups[pair] += ', '+(start_pair.join ':') if modify_group_names
			else
				@groups[pair] = "reached from #{start_pair.join ':'}"
			end
		end
	end
	
	def gather_from_many pairs
		pairs.each{|pair| gather_from *pair}
	end
	
	def follow_redirects pairs
		pairs.map do |wiki, title|
			s = get_sf wiki
			res = s.API action:'query', titles:title, redirects:true
			if res['query']['redirects']
				[wiki, res['query']['redirects'][0]['to'] ]
			else
				[wiki, title]
			end
		end
	end
	
	
	
	def pretty_iw pairs
		pairs.map{|a| "[[#{a.join ':'}]]"}
	end
	
	# Log in all wikis. Returns true on success.
	def login_all user, pass
		puts 'logging in... (wait)'
		i = 0
		@sf.p_each(5) do |kv|
			wiki, s = *kv
			s.login CGI.escape(user), CGI.escape(pass)
			
			print "#{i+1}/#{@sf.length}\r"
			i+=1
		end
		return true
	end
	
	def find_all_matching wiki, selector=nil
		allowed_wikis = case wiki
		when '*'
			@all.map{|a| a[0]}.uniq
		when /,/
			wiki.split(',')
		else
			[ wiki ]
		end
		
		initial_list = @all.select{|pair| allowed_wikis.include? pair[0]}
		return initial_list if !selector
		
		if selector =~ /\A[\d,]+\Z/
			return initial_list.values_at *selector.split(',').map(&:to_i)
		else
			if selector[0]=='/' and selector[-1]=='/'
				regex = Regexp.new selector[1..-2], Regexp::IGNORECASE
			else
				regex = Regexp.new Regexp.escape(selector), Regexp::IGNORECASE
			end
			
			return initial_list.select{|pair| pair[1] =~ regex}
		end
	end
	
	def command_help
		puts 'commands:'
		puts [
			'help',
			'show',
			'showg',
			'summary <text>',
			'linksto <lang> <title>',
			'linksfrom <lang> <title>',
			'start <lang> <title>',
			'start <lang>',
			'rename <group> <group>',
			'move <lang> <regex> <group>',
			'move * <regex> <group>',
			'gather <lang> <title>',
			'commit',
			'exit',
		]
	end
	
	def command_exit
		exit
	end
	
	def command_show
		@all.each do |pair|
			puts "#{pair.join(':').encode('cp852', undef: :replace).ljust 40, '.'}#{@groups[pair].encode('cp852', undef: :replace)}"
		end
	end
	
	def command_showg
		lists_per_group = {} # {groupname => [pairs]}
		@groups.each_pair do |pair, group|
			lists_per_group[group] ||= []
			lists_per_group[group] << pair
		end
		lists_per_group.each_value{|gr| gr.sort!}
		
		lists_per_group.each_pair do |group, pairs|
			puts ">>> #{group}"
			puts pretty_iw pairs
			puts ''
		end
	end
	
	def command_summary summ
		@summary_user = summ.to_s
	end
	
	def command_linksfrom wiki, title
		puts pretty_iw @linksfrom[ [wiki, title] ]
	end
	
	def command_linksto wiki, title
		puts pretty_iw @linksto[ [wiki, title] ]
	end
	
	def command_start wiki
		pairs = wiki=='*' ? @all : @all.select{|pair| pair[0] == wiki}
		pairs.each{|wiki, title| Launchy.open "http://#{wiki}.wikipedia.org/w/index.php?title=#{CGI.escape title}" }
	end
	
	def command_move wiki, name_reg, target_group
		if wiki == '*'
			got = @all.select{|pair| name_reg=~pair[1]}
			got.each do |pair|
				@groups[pair] = target_group
			end
		else
			got = @all.select{|pair| pair[0]==wiki and name_reg=~pair[1]}
			if got.length==1
				pair = got[0]
				@groups[pair] = target_group
			elsif got.empty?
				puts 'uh oh. no matches!'
			else
				puts 'uh oh. multiple matches!'
			end
		end
	end
	
	def command_gather wiki, title
		gather_from wiki, title
	end
	
	def command_rename from, to
		@groups.each_key do |k|
			@groups[k] = to if @groups[k]==from
		end
	end
	
	def command_find wiki, selector
		puts pretty_iw find_all_matching(wiki, selector)
	end
	
	def command_commit
		if @logged_in
			puts "are you sure you know what you're doing? (yes/no)"
			if gets.strip.downcase=='yes'
				lists_per_group = {} # {groupname => [pairs]}
				@groups.each_pair do |pair, group|
					lists_per_group[group] ||= []
					lists_per_group[group] << pair
				end
				lists_per_group.each_value{|gr| gr.sort!}
				
				# pp lists_per_group
				# gets
				
				clear_iw_regex = /\[\[(?:#{@all.map{|a| a[0]}.uniq.join '|'}):.+?\]\](?:\r?\n)?/
				# p clear_iw_regex
				# gets
				
				if !@summary_user
					puts 'no summary given.'
					return
				end
				
				@summary_base = "semiautomatically fixing interwiki conflicts (trouble?: [[#{@homewiki}:User talk:#{@user}]])"
				@summary = @summary_base + ' - ' + @summary_user
				
				@sf.each_with_index do |kv, i|
					wiki, s = *kv
					s.summary = @summary
				end
				
				lists_per_group.each_pair do |group, pairs|
					next if group=='donttouch' or group=~/\Areached from/
					puts group+'...'
					
					pairs.each do |pair|
						wiki, title = *pair
						page = Page.new title, wiki
						
						if page.text.scan(clear_iw_regex).sort == pretty_iw(pairs-[pair]).sort
							puts "#{(pretty_iw [pair])[0]} - no changes needed"
						else
							page.text = (page.text.gsub clear_iw_regex, '').strip
							page.text += "\n\n" + pretty_iw(pairs-[pair]).join("\n") unless group=='clear'
							
							res = page.save
							if res != nil
								puts "#{(pretty_iw [pair])[0]} #{res['edit']['result']=="Success" ? 'saved' : 'failure!!!' rescue 'failure!!!'}"
							else
								puts "#{(pretty_iw [pair])[0]} - no changes needed"
							end
							
							gets
						end
					end
				end
				
				puts 'done!'
				
			else
				puts 'aborted.'
			end
		else
			puts 'not logged in!'
		end
	end
	
	def command_login
		if @logged_in
			puts "already logged in as #{@user} on #{@homewiki}"
		else
			puts 'log in to edit (leave empty to just preview):'
			puts '[password will be visible!]'
			print 'homewiki: '; home = gets.strip
			print 'username: '; user = gets.strip
			print 'password: '; pass = gets.strip

			do_log_in = (user!='' and pass!='')
			if do_log_in
				@logged_in = login_all(user, pass) 
				@user = user
				@homewiki = home
				puts 'logged in.'
			else
				puts 'did nothing.'
			end
		end
	end
	
	def process_command line
		case line
		when ''
			# pass
			
		when 'help'; command_help
			
		when 'exit'; command_exit
			
		when 'show'; command_show
			
		when 'showg'; command_showg
			
		when /\Asummary (.+)\Z/
			command_summary $1
			
		when /\Alinksfrom ([a-z-]+) (.+)\Z/
			command_linksfrom $1, $2
			
		when /\Alinksto ([a-z-]+) (.+)\Z/
			command_linksto $1, $2
		
		when /\Astart (\*|[a-z-]+)\Z/
			command_start $1
			
		when /\Amove (\*|[a-z-]+) (.+?) ([a-z0-9]+)\Z/, /\Amove (\*|[a-z-]+) ()([a-z0-9]+)\Z/
			command_move $1, /#{$2}/i, $3
		
		when /\Agather ([a-z-]+) (.+)\Z/
			command_gather $1, $2
			
		when /\A(?:rename|merge) ([a-z0-9]+) ([a-z0-9]+)\Z/
			command_rename $1, $2
			
		when /\Afind ([a-z\-,]+|\*) (.+)\Z/,  /\Afind ([a-z\-,]+|\*)\Z/
			command_find $1, $2
			
		when 'commit'
			command_commit
			
		when 'login'
			command_login
			
		else
			puts "d'oh? incorrect command."
		end
	end
	
	def busy_loop
		puts "#{@all.length} articles in #{@sf.length} languages."
		puts ''
		
		command_login
		
		while true
			print '> '
			read = gets.strip
			process_command read
		end
	end
end



if __FILE__ == $0
	start_pairs = ARGV.map{|title| title.split(':', 2) }

	iw = InterwikiConflictSolver.new
	iw.gather_from_many start_pairs
	ARGV.pop until ARGV.empty?

	iw.busy_loop
end
