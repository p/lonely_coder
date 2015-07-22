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
    Profile.update_profile_section(section, text, @browser)
  end

  def upload_pic(file, caption)
    Profile.upload_picture(file, caption, @browser)
  end
  
  class Profile
    attr_accessor :username, :match, :friend, :enemy, :location,
                  :age, :sex, :orientation, :relationship_status,
                  :gentation, :ages, :near, :looking_for, :looking_for_single,
                  :small_avatar_url, :relationship_type

    # extended profile details
    attr_accessor :last_online, :ethnicity, :height, :body_type, :diet, :smokes,
                  :drinks, :drugs, :religion, :sign, :education, :job, :income,
                  :offspring, :pets, :speaks, :profile_thumb_urls, :essays


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
        relationship_type: relationship_type,
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
      10.times do |i|
        essays[i] = html.search('#essay_text_' + i.to_s).text.strip!
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
        relationship_type: relationship_type,
        essays: essays,
      }

      details_div = html.search('#profile_details dl')

      details_div.each do |node|
        node.search('dd script').map(&:remove)
        
        value = OKCupid.strip(node.search('dd').text)
        next if value == '—'

        attr_name = node.search('dt').text.strip.downcase.gsub(' ','_')
        attributes[attr_name] = value
      end

      self.new(attributes)
    end

    def Profile.update_profile_section(section, text, browser)
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
      
      profile = browser.get('http://www.okcupid.com/profile')

      authcode = profile.body.match(/authcode['"]?\s*:\s*['"]([\w,;]+?)['"]/)[1]

      section_response = browser.post('http://www.okcupid.com/profileedit2', {
        :authcode => authcode,
        :essay_body => text,
        :essay_id => section,
        :change_summary => "[title:start]#{section_titles[section]}[title:end][add:start]#{text}[add:end]",
        :okc_api => 1
      })
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

