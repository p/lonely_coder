# encoding: UTF-8

class OKCupid

  def profile_for(username)
    Profile.by_username(username, @browser)
  end

  def visitors_for(username, previous_timestamp = 0)
    Profile.get_new_visitors(username, previous_timestamp, @browser)
  end

  def likes_for(username)
    Profile.get_new_likes(username, @browser)
  end

  def update_section(section, text)
    Profile.update_profile_section(section, text, @browser, @authentication)
  end

  def upload_pic(file, caption)
    Profile.upload_picture(file, caption, @browser)
  end
  
  class Profile
    attr_accessor :username, :match, :friend, :enemy, :location, :distance,
                  :age, :sex, :orientation, :relationship_status,
                  :gentation, :ages, :near, :looking_for, :looking_for_single,
                  :small_avatar_url

    # extended profile details
    attr_accessor :last_online, :ethnicity, :height, :body_type, :diet,
                  :special_diet, :smoking,
                  :drinking, :drugs, :religion, :sign, :education, :job, :income,
                  :offspring, :pets, :speaks, :profile_thumb_urls, :essays


    def self.essay_keys
      {
        "My self-summary" => 0,
        "What I\u2019m doing with my life" => 1,
        "I\u2019m really good at" => 2,
        "The first things people usually notice about me" => 3,
        "Favorite books, movies, shows, music, and food" => 4,
        "The six things I could never do without" => 5,
        "I spend a lot of time thinking about" => 6,
        "On a typical Friday night I am" => 7,
        "The most private thing I\u2019m willing to admit" => 8,
        "You should message me if" => 9,
      }
    end

    # Scraping is never pretty.
    def self.from_search_result(html)

      username = html.search('span.username').text
      age, sex, orientation, relationship_status = html.search('p.aso').text.split('/')

      percents = html.search('div.percentages')
      match = percents.search('p.match .percentage').text.to_i
      enemy = percents.search('p.enemy .percentage').text.to_i

      location = html.search('p.location').text
      small_avatar_url = html.search('a.user_image img').attribute('src').value

      OKCupid::Profile.new({
        username: username,
        age: OKCupid.strip(age),
        sex: OKCupid.strip(sex),
        orientation: OKCupid.strip(orientation),
        relationship_status: OKCupid.strip(relationship_status),
        match: match,
        enemy: enemy,
        location: location,
        small_avatar_url: small_avatar_url,
      })
    end

    def Profile.get_new_likes(username, browser)
      html = browser.get("http://www.okcupid.com/who-likes-you")
      text = html.search('#whosIntoYouUpgrade .title').text
      index = text.index(' people')
      likes = text[0, index].to_i

      return likes
    end

    def Profile.get_new_visitors(username, previous_timestamp = 1393545600, browser)
      html = browser.get("http://www.okcupid.com/visitors")
      visitors = html.search(".user_list .user_row_item")

      new_visitors = 0
      # previous_timestamp = 1393545600

      visitors.each { |visitor|
          begin
            timestamp_script = visitor.search(".timestamp script")
            timestamp_search = timestamp_script.text.match(/FancyDate\.add\([^,]+?,\s*(\d+)\s*,/)
            timestamp = timestamp_search[1]
            timestamp = timestamp.to_i
          rescue
            next
          end
          if (timestamp > previous_timestamp)
            new_visitors += 1
          end
      }

      return new_visitors
    end
    
    class Essay
      attr_reader :index
      attr_reader :title
      attr_reader :content
      
      def initialize(index, title, content)
        @index = index
        @title = title
        @content = content
      end
      
      def to_hash
        {index: self.index, title: self.title, content: self.content}
      end
    end

    def Profile.by_username(username, browser)
      html = browser.get("http://www.okcupid.com/profile/#{username}")

      percents = html.search('#percentages')
      match = percents.search('.match .percent').text.to_i
      enemy = percents.search('.enemy .percent').text.to_i

      basic = html.search('#aso_loc')
      age = basic.search('#ajax_age').text.to_i
      sex = basic.search('.infos .ajax_gender').text
      gentation = html.search('#ajax_gentation').text.strip
      ages = html.search('#ajax_gentation').text.strip
      near = html.search('#ajax_near').text.strip
      looking_for_single = html.search('#ajax_single').text.strip
      looking_for = html.search('#ajax_lookingfor').text.strip
      relationship_status = html.search('#ajax_status').text.strip
      location = basic.search('#ajax_location').text
      distance = basic.search('.dist').text.strip.sub(%r/\A\((.+)\)\z/, '\1')
      profile_thumb_urls = html.search('#profile_thumbs img').collect {|img| img.attribute('src').value}

      essays = []
      html.search('.essays2015-essay').each do |essay|
        title = essay.search('.essays2015-essay-title').text.strip!
        content = essay.search('.essays2015-essay-content').text.strip!
        index = Profile.essay_keys[title]
        if not index
          raise "Could not find index for title: #{title}"
        end
        essays[index] = Essay.new(index, title, content)
      end

      attributes = {
        username: username,
        match: match,
        enemy: enemy,
        age: age,
        sex: sex,
        gentation: gentation,
        ages: ages,
        near: near,
        looking_for_single: looking_for_single,
        looking_for: looking_for,
        location: location,
        distance: distance,
        relationship_status: relationship_status,
        profile_thumb_urls: profile_thumb_urls,
        essays: essays,
      }

      details_div = html.search('#profile_details dl')

      details_div.each do |node|
        node.search('dd script').map(&:remove)
        
        value = OKCupid.strip(node.search('dd').text)
        next if value == '—'

        attr_name = node.search('dt').text.strip.downcase.gsub(' ','_')
        if attr_name == 'status'
          attr_name = 'relationship_status'
        end
        attributes[attr_name] = value
      end

      self.new(attributes)
    end

    def Profile.update_profile_section(section, text, browser, authentication)
      section_titles = [
        "My self-summary",
        "What I’m doing with my life",
        "I’m really good at",
        "The first things people usually notice about me",
        "Favorite books, movies, shows, music, and food",
        "The six things I could never do without",
        "I spend a lot of time thinking about",
        "On a typical Friday night I am",
        "The most private thing I’m willing to admit",
        "You should message me if"
      ]

      section_titles_hash = {
        :self_summary => 0,
        :im_doing => 1,
        :good_at => 2,
        :first_thing => 3,
        :favorites => 4,
        :six_things => 5,
        :think_about => 6,
        :private => 7,
        :message_me => 8
      }

      if section.class == Symbol
        section = section_titles_hash[section]
      end
      
      browser.post('https://www.okcupid.com/1/apitun/profile/edit/essays',
        {'essays' => {section.to_s => text}}.to_json,
        {'Authorization' => "Bearer #{authentication.access_token}",
        'Content-Type' => 'application/json'},
      )
    end

    def Profile.upload_picture(file, caption, browser)

      file_dimensions = Dimensions.dimensions(file)

      profile = browser.get('http://www.okcupid.com/profile')

      authcode = profile.body.match(/authcode['"]?\s*:\s*['"]([\w,;]+?)['"]/)[1]
      userid = profile.body.match(/userid['"]?\s*:\s*['"]?(\d+)['"]?/)[1]

      upload_response = browser.post('http://www.okcupid.com/ajaxuploader', {
        'file' => File.new(file)
      })

      picid = upload_response.body.match(/id'\s*:\s*'(\d+)/)[1]

      uri = Addressable::URI.parse('http://www.okcupid.com/photoupload')
      uri.query_values = {
        :authcode => authcode,
        :userid => userid,
        :picid => picid,
        :width => file_dimensions[0],
        :height => file_dimensions[1],
        :tn_upper_left_x => 0,
        :tn_upper_left_y => 0,
        :tn_lower_right_x => file_dimensions[0],
        :tn_lower_right_y => file_dimensions[1],

        :caption => caption,
        :albumid => 0,
        :use_new_upload => 1,
        :okc_api => 1,
        :'picture.add_ajax' => 1,
      }
      
      uri.to_s

      create_photo = browser.get(uri.to_s)

    end
    
    def initialize(attributes)
      attributes.each do |attr,val|
        self.send("#{attr}=", val)
      end
    end

    def ==(other)
      self.username == other.username
    end

    def eql?(other)
      self.username == other.username
    end

    def hash
      if self.username
        self.username.hash
      else
        super
      end
    end
  end
end

