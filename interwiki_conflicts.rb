# coding: utf-8
require 'sunflower'
require 'launchy'
begin
	require 'graph'
rescue LoadError
	puts "Gem 'graph' is not installed. You will not be able to see the connections graph."
end

require 'pp'


class InterwikiConflictSolver
	attr_accessor :all, :groups, :summary
	def initialize opts
		@enc = opts[:output_encoding]
		
		@sf = {}
		@history = []
		
		@all = []
		@groups = {}
		
		@linksfrom = {}
		@linksto = {}
		
		@summary = @summary_base = ''
		@logged_in_wikis = []
	end
	
	# Creates a Sunflower with customized settings and returns it; keeps a cache.
	def get_sf wiki
		if !@sf[wiki]
			@sf[wiki] = Sunflower.new wiki
		
			@sf[wiki].warnings = false
			@sf[wiki].summary = @summary
		end
		
		return @sf[wiki]
	end
	
	# Finds articles interwikilinked from the starting one.
	def gather_from wiki, article, to_group=nil
		start_pair = [wiki, article]
		start_pair = (canonicalize_titles [start_pair]).first
		
		results = []
		results << start_pair
		
		queue = []
		queue << start_pair
		
		while now = queue.shift
			if @all.include? now
				puts "skipping #{now.join ':'} - already reached"
				next
			end
			
			wiki, article = *now
			puts "#{wiki.ljust 8} #{queue.length} left"
			
			s = get_sf wiki
			res = s.API action:'query', prop:'langlinks', lllimit:500, titles:article
			iwlinks = (res['query']['pages'].values.first['langlinks'] || []).map{|hsh| [ hsh['lang'], hsh['*'] ] }
			iwlinks = (canonicalize_titles iwlinks).uniq
			
			iwlinks.each do |pair|
				@linksto[pair] ||= []
				@linksto[pair] << now
			end
			
			@linksfrom[now] ||= []
			@linksfrom[now] += iwlinks
			
			iwlinks.each do |pair|
				unless results.include? pair
					if pair[1] =~ /#/
						puts "ignoring #{pair.join ':'} - link to section"
						next
					else
						results << pair
						queue << pair
					end
				end
			end
		end
		
		@all += results
		@all.uniq!
		@all.sort!
		
		results.each do |pair|
			if !@groups[pair]
				@groups[pair] = to_group || "reached from #{start_pair.join ':'}"
			end
		end
	end
	
	def gather_from_many pairs
		pairs.each{|pair| gather_from *pair}
	end
	
	def canonicalize_titles pairs
		@__canon_map ||= {}
		
		pairs.map do |wiki, title|
			key = [wiki.dup, title.dup]
			
			if @__canon_map[key]
				@__canon_map[key]
			else
				s = get_sf wiki
				title = s.cleanup_title(title)
				
				res = s.API action:'query', titles:title, redirects:true
				if res['query']['redirects']
					@__canon_map[key] = [wiki, res['query']['redirects'][0]['to'] ]
				else
					@__canon_map[key] = [wiki, title]
				end
			end
		end
	end
	
	
	# Pretty-prints wikilinks; returns an array!
	def pretty_iw pairs
		pairs.map{|a| "[[#{a.join ':'}]]"}
	end
	
	# Log in all wikis. Returns true on success. (Which is currently always.)
	def login_all user, pass
		@logged_in_wikis = []
		puts 'logging in... (wait)'
		@sf.each_with_index do |kv, i|
			wiki, s = *kv
			s.login user, pass
			
			print "#{i+1}/#{@sf.length}\r"
			@logged_in_wikis << wiki
		end
		
		@logged_in_wikis.sort!; @logged_in_wikis.uniq!
		return true
	end
	
	# Finds all articles that match specific criteria.
	# 
	# Possible syntaxes for wiki are:
	#   * an asterisk - all wikis
	#   * comma-separated list - exactly these wikis
	#   * single wiki
	# 
	# Possible syntaxes for selector are:
	#   * nothing - returns everything matching wiki criteria
	#   * comma-separated list of numbers - exactly these entries
	#   * /regexp/ - entries matching the regexp (case-insensitive)
	#   * other - entries where it is a substring (case-insensitive)
	# 
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
		
		if !selector or selector.strip == ''
			return initial_list
		elsif selector =~ /\A[\d,]+\Z/
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
		puts <<-EOF.gsub(/^\t\t/, '').gsub(/^(\t+)/){'  ' * $1.length}
		Available commands:
			help
				Shows this message.
			summary <text>
				Sets the summary for your edits.
			gather <lang> <title> <group[opt]>
				Starting from given article, finds all that can be reached via interwiki links. Optionally puts them into group.
			show
				Shows list of all articles on all wikis that you are about to edit interwiki on.
			showg
				As above, by groups.
			find <~lang> <~title>
				Finds all article titles matching given selectors (see below).
			move <~lang> <~title> <group>
				Moves article(s) to group.
			start <~lang> <~title>
				Opens articles(s) Wiki pages in default browser.
			starttr <~lang> <~title>
				Opens Google Translate for articles(s) in default browser.
			rename <group> <group>
			merge <group> <group>
				Renames group, or merges two groups together.
			graph
				Generates a graph of interwiki connections using Graphviz. Saves files in current directory.
			commit
				Saves your changes on all wikis. Prompts you for username and password.
			linksto <lang> <title>
				Lists articles from which you can currently reach given article.
			linksfrom <lang> <title>
				Lists articles reachable from given article.
			history
				Prints history of commands used.
			exit
				Exits the tool.
		
		Formats used above:
			<lang>
				Wikipedia language code, for example en, de, or be-x-old.
			<title>
				Title of Wiki article, without language prefix. Effectively anything.
			<group>
				A name of group. Only loewrcase letters (a-z) and numbers.
			<text>
				Any text.
			<~lang>
				Language selector - a single language, comma-separated list of languages, or an asterisk * - every language.
			<~title>
				Title selector - nothing (matches all), comma-separated list of numbers, regular expression, or title substring.
		EOF
	end
	
	def command_history
		puts @history
	end
	
	def command_exit
		exit
	end
	
	def command_show
		@all.each do |pair|
			puts "#{pair.join(':').encode(@enc, undef: :replace).ljust 40, '.'}#{@groups[pair].encode(@enc, undef: :replace)}"
		end
	end
	
	def command_showg
		lists_per_group = {} # {groupname => [pairs]}
		@groups.each_pair do |pair, group|
			lists_per_group[group] ||= []
			lists_per_group[group] << pair
		end
		lists_per_group.each_value{|gr| gr.sort!}
		
		lists_per_group.keys.sort.each do |group|
			pairs = lists_per_group[group]
			puts ">>> #{group}"
			puts pretty_iw(pairs).map{|ln| ln.encode(@enc, undef: :replace)}
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
	
	def command_start wiki_s, title_s
		pairs = find_all_matching wiki_s, title_s
		pairs.each{|wiki, title| Launchy.open "http://#{wiki}.wikipedia.org/w/index.php?title=#{CGI.escape title}" }
	end
	
	def command_starttr wiki_s, title_s
		pairs = find_all_matching wiki_s, title_s
		pairs.each{|wiki, title|
			wikiurl = "http://#{wiki}.wikipedia.org/w/index.php?title=#{CGI.escape title}"
			Launchy.open "http://translate.google.com/translate?sl=#{wiki}&u=#{CGI.escape wikiurl}"
		}
	end
	
	def command_move wiki_s, title_s, target_group
		got = find_all_matching wiki_s, title_s
		got.each do |pair|
			@groups[pair] = target_group
		end
	end
	
	def command_gather wiki, title, to_group=nil
		gather_from wiki, title, (to_group && to_group.strip!='' ? to_group : nil)
	end
	
	def command_rename from, to
		@groups.each_key do |k|
			@groups[k] = to if @groups[k]==from
		end
	end
	
	def command_find wiki_s, title_s
		puts pretty_iw find_all_matching(wiki_s, title_s)
	end
	
	def command_commit
		puts "are you sure you know what you're doing? (yes/no)"
		if gets.strip.downcase=='yes'
			# make sure everything is okay
			if !@summary_user
				puts 'no summary given.'
				return
			end
			
			if @logged_in_wikis != @all.map{|a| a[0]}.uniq.sort
				puts 'you have not yet logged in into all wikis. do it now:'
				return if !do_login
			end
			
			@summary = "semiautomatically fixing interwiki conflicts using [[pl:User:Matma Rex/ICS|ICS]]: #{@summary_user} (trouble?: [[#{@homewiki}:User talk:#{@user}]])"
			
			@sf.each_with_index do |kv, i|
				wiki, s = *kv
				s.summary = @summary
			end
			
			# right. all is well. we should not fail beyond this point...
			lists_per_group = {} # {groupname => [pairs]}
			@groups.each_pair do |pair, group|
				lists_per_group[group] ||= []
				lists_per_group[group] << pair
			end
			lists_per_group.each_value{|gr| gr.sort!}
			
			clear_iw_regex = /\[\[(?:#{@all.map{|a| a[0]}.uniq.join '|'}):.+?\]\](?:\r?\n)?/
			
			continue = false
			noticeshown = false
			
			lists_per_group.each_pair do |group, pairs|
				next if group=='donttouch' or group=~/\Areached from/
				puts group+'...'
				
				pairs.each do |pair|
					wiki, title = *pair
					page = Sunflower::Page.new title, wiki
					
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
						
						if !continue
							if !noticeshown
								noticeshown = true
								puts "press enter to continue with next article; type in 'ok' and press enter to continue with all"
							end
							m = gets.strip.downcase
							continue = (m == 'ok')
						end
					end
				end
			end
			
			puts 'done!'
			
		else
			puts 'aborted.'
		end
	end
	
	def command_graph
		unless Graph
			puts "'graph' gem not available."
			return
		end
		
		g = Graph.new
		@linksfrom.each_pair do |from, to_list|
			to_list.each do |to|
				g.edge from.join(':'), to.join(':')
			end
		end
		
		path = "#{Dir.pwd}/wikigraph-#{Time.now.strftime "%Y%m%d-%H%m%S"}"
		dotpath = "#{path}.dot"
		svgpath = "#{path}.svg"
		
		File.open(dotpath, 'w'){|f| f.write g.to_s}
		puts "Dotfile saved, processing..."
		
		ret = system 'circo', dotpath, '-o', svgpath, '-T', 'svg'
		if ret
			puts "Saved files to current directory!"
		else
			puts "Graphviz not installed. Graph not generated."
		end
	end
	
	def command_do code
		begin
			p eval code
		rescue Exception
			p $!
		end
	end
	
	def do_login
		puts 'log in to edit (leave empty to just preview):'
		puts '[password will be visible!]'
		print 'homewiki: '; home = gets.strip
		print 'username: '; user = gets.strip
		print 'password: '; pass = gets.strip

		do_log_in = (user!='' and pass!='')
		if do_log_in
			begin
				@logged_in = login_all(user, pass) 
				@user = user
				@homewiki = home
				puts 'logged in.'
				return true
			rescue SunflowerError => e
				puts "couldn't login - wrong username or password? (error was: #{e.message})"
				return false
			end
		else
			puts 'did nothing.'
			return false
		end
	end
	
	def process_command line
		return if line.empty?
		@history << line
		
		case line
		when 'help'; command_help
			
		when 'history'; command_history
			
		when 'exit'; command_exit
			
		when 'show'; command_show
			
		when 'showg'; command_showg
			
		when /\Asummary (.+)\Z/
			command_summary $1
			
		when /\Alinksfrom ([a-z-]+) (.+)\Z/
			command_linksfrom $1, $2
			
		when /\Alinksto ([a-z-]+) (.+)\Z/
			command_linksto $1, $2
		
		when /\Astart (\*|[a-z,-]+)(?: (.+))?\Z/
			command_start $1, $2
			
		when /\Astarttr (\*|[a-z,-]+)(?: (.+))?\Z/
			command_starttr $1, $2
			
		when /\Amove (\*|[a-z,-]+)(?: (.+))? ([a-z0-9]+)\Z/
			command_move $1, $2, $3
		
		when /\Agather ([a-z-]+) (.+)(?: ([a-z0-9]+))?\Z/
			command_gather $1, $2, $3
			
		when /\A(?:rename|merge) ([a-z0-9]+) ([a-z0-9]+)\Z/, /\A(?:rename|merge) "([^"]+)" ([a-z0-9]+)\Z/
			command_rename $1, $2
			
		when /\Afind (\*|[a-z,-]+)(?: (.+))?\Z/
			command_find $1, $2
			
		when 'commit'
			command_commit
		
		when 'graph'
			command_graph
			
		when /\Ado (.+)\Z/
			command_do $1
			
		else
			puts "d'oh? incorrect command."
		end
	end
	
	def busy_loop
		puts "InterwikiConflictSolver v. 0.2.2"
		puts "Type 'help' to get started."
		while true
			begin
				print '> '
				read = gets.strip
				process_command read
			rescue SyntaxError, StandardError => e
				puts 'whoops. something broke. the error is: '+e.to_s
				puts e.backtrace
			end
		end
	end
end



if __FILE__ == $0
	iw = InterwikiConflictSolver.new(output_encoding: ARGV.pop || 'cp852')
	iw.busy_loop
end
