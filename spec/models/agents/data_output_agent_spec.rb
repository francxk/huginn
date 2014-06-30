# encoding: utf-8

require 'spec_helper'

describe Agents::DataOutputAgent do
  let(:agent) do
    _agent = Agents::DataOutputAgent.new(:name => 'My Data Output Agent')
    _agent.options = _agent.default_options.merge('secrets' => ['secret1', 'secret2'], 'events_to_show' => 2)
    _agent.user = users(:bob)
    _agent.sources << agents(:bob_website_agent)
    _agent.save!
    _agent
  end

  describe "#working?" do
    it "checks if events have been received within expected receive period" do
      agent.should_not be_working
      Agents::DataOutputAgent.async_receive agent.id, [events(:bob_website_agent_event).id]
      agent.reload.should be_working
      two_days_from_now = 2.days.from_now
      stub(Time).now { two_days_from_now }
      agent.reload.should_not be_working
    end
  end

  describe "validation" do
    before do
      agent.should be_valid
    end

    it "should validate presence and length of secrets" do
      agent.options[:secrets] = ""
      agent.should_not be_valid
      agent.options[:secrets] = "foo"
      agent.should_not be_valid
      agent.options[:secrets] = []
      agent.should_not be_valid
      agent.options[:secrets] = ["hello"]
      agent.should be_valid
      agent.options[:secrets] = ["hello", "world"]
      agent.should be_valid
    end

    it "should validate presence of expected_receive_period_in_days" do
      agent.options[:expected_receive_period_in_days] = ""
      agent.should_not be_valid
      agent.options[:expected_receive_period_in_days] = 0
      agent.should_not be_valid
      agent.options[:expected_receive_period_in_days] = -1
      agent.should_not be_valid
    end

    it "should validate presence of template and template.item" do
      agent.options[:template] = ""
      agent.should_not be_valid
      agent.options[:template] = {}
      agent.should_not be_valid
      agent.options[:template] = { 'item' => 'foo' }
      agent.should_not be_valid
      agent.options[:template] = { 'item' => { 'title' => 'hi' } }
      agent.should be_valid
    end
  end

  describe "#receive_web_request" do
    before do
      current_time = Time.now
      stub(Time).now { current_time }
      agents(:bob_website_agent).events.destroy_all
    end

    it "requires a valid secret" do
      content, status, content_type = agent.receive_web_request({ 'secret' => 'fake' }, 'get', 'text/xml')
      status.should == 401
      content.should == "Not Authorized"

      content, status, content_type = agent.receive_web_request({ 'secret' => 'fake' }, 'get', 'application/json')
      status.should == 401
      content.should == { :error => "Not Authorized" }

      content, status, content_type = agent.receive_web_request({ 'secret' => 'secret1' }, 'get', 'application/json')
      status.should == 200
    end

    describe "returning events as RSS and JSON" do
      let!(:event1) do
        agents(:bob_website_agent).create_event :payload => {
          "url" => "http://imgs.xkcd.com/comics/evolving.png",
          "title" => "Evolving",
          "hovertext" => "Biologists play reverse Pokemon, trying to avoid putting any one team member on the front lines long enough for the experience to cause evolution."
        }
      end

      let!(:event2) do
        agents(:bob_website_agent).create_event :payload => {
          "url" => "http://imgs.xkcd.com/comics/evolving2.png",
          "title" => "Evolving again",
          "hovertext" => "Something else"
        }
      end

      it "can output RSS" do
        stub(agent).feed_link { "https://yoursite.com" }
        content, status, content_type = agent.receive_web_request({ 'secret' => 'secret1' }, 'get', 'text/xml')
        status.should == 200
        content_type.should == 'text/xml'
        content.gsub(/\s+/, '').should == Utils.unindent(<<-XML).gsub(/\s+/, '')
          <?xml version="1.0" encoding="UTF-8" ?>
          <rss version="2.0">
          <channel>
           <title>XKCD comics as a feed</title>
           <description>This is a feed of recent XKCD comics, generated by Huginn</description>
           <link>https://yoursite.com</link>
           <lastBuildDate>#{Time.now.rfc2822}</lastBuildDate>
           <pubDate>#{Time.now.rfc2822}</pubDate>
           <ttl>60</ttl>

           <item>
            <title>Evolving again</title>
            <description>Secret hovertext: Something else</description>
            <link>http://imgs.xkcd.com/comics/evolving2.png</link>
            <guid>#{event2.id}</guid>
            <pubDate>#{event2.created_at.rfc2822}</pubDate>
           </item>

           <item>
            <title>Evolving</title>
            <description>Secret hovertext: Biologists play reverse Pokemon, trying to avoid putting any one team member on the front lines long enough for the experience to cause evolution.</description>
            <link>http://imgs.xkcd.com/comics/evolving.png</link>
            <guid>#{event1.id}</guid>
            <pubDate>#{event1.created_at.rfc2822}</pubDate>
           </item>

          </channel>
          </rss>
        XML
      end

      it "can output JSON" do
        agent.options['template']['item']['foo'] = "hi"

        content, status, content_type = agent.receive_web_request({ 'secret' => 'secret2' }, 'get', 'application/json')
        status.should == 200

        content.should == {
          'title' => 'XKCD comics as a feed',
          'description' => 'This is a feed of recent XKCD comics, generated by Huginn',
          'pubDate' => Time.now,
          'items' => [
            {
              'title' => 'Evolving again',
              'description' => 'Secret hovertext: Something else',
              'link' => 'http://imgs.xkcd.com/comics/evolving2.png',
              'guid' => event2.id,
              'pubDate' => event2.created_at.rfc2822,
              'foo' => 'hi'
            },
            {
              'title' => 'Evolving',
              'description' => 'Secret hovertext: Biologists play reverse Pokemon, trying to avoid putting any one team member on the front lines long enough for the experience to cause evolution.',
              'link' => 'http://imgs.xkcd.com/comics/evolving.png',
              'guid' => event1.id,
              'pubDate' => event1.created_at.rfc2822,
              'foo' => 'hi'
            }
          ]
        }
      end
    end
  end
end
