require 'fluent/test'
require 'helper'

class FastlyInputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
    require 'fluent/plugin/socket_util'
  end

  PORT = unused_port
  CONFIG = %[
    port #{PORT}
    bind 127.0.0.1
    tag fastly
  ]

  IPv6_CONFIG = %[
    port #{PORT}
    bind ::1
    tag fastly
  ]

  def create_driver(conf=CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::FastlyInput).configure(conf)
  end

  def test_configure
    configs = {'127.0.0.1' => CONFIG}
    configs.merge!('::1' => IPv6_CONFIG) if ipv6_enabled?

    configs.each_pair { |k, v|
      d = create_driver(v)
      assert_equal PORT, d.instance.port
      assert_equal k, d.instance.bind
    }
  end

  def test_time_format
    configs = {'127.0.0.1' => CONFIG}
    configs.merge!('::1' => IPv6_CONFIG) if ipv6_enabled?

    configs.each_pair { |k, v|
      d = create_driver(v)

      tests = [
        {'msg' => "<134>2014-07-10T23:18:15Z cache-hk91 td.server.requests[11226]: {\"ip\":\"166.137.213.198\",\"client_id\":\"17a8e5f8f64a9a7c85d1ccab51bcfdf6\",\"status\":200,\"user_agent\":\"Mozilla/5.0 (iPhone; CPU iPhone OS 7_0_3 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11B511 Safari/9537.53\",\"null_val\":\"(null)\"}", 'expected' => Time.new(2014,7,10,23,18,15).to_i },

        {'msg' => "<134>2014-07-13T14:57:46Z cache-dfw1829 td.server.requests[524]: {\"ip\":\"166.137.213.198\",\"client_id\":\"17a8e5f8f64a9a7c85d1ccab51bcfdf6\",\"status\":200,\"user_agent\":\"Mozilla/5.0 (iPhone; CPU iPhone OS 7_0_3 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11B511 Safari/9537.53\",\"null_val\":\"(null)\"}", 'expected' => Time.new(2014,07,13,14,57,46).to_i}

      ]


      d.run do
        u = Fluent::SocketUtil.create_udp_socket(k)
        u.connect(k, PORT)
        tests.each {|test|
          u.send(test['msg'], 0)
        }
        sleep 1
      end

      emits = d.emits

      tests.each_index  {|i|

        assert_equal(tests[i]['expected'], emits[i][1])
      }
    }
  end

  def test_param_splitting


    configs = {'127.0.0.1' => CONFIG}
    configs.merge!('::1' => IPv6_CONFIG) if ipv6_enabled?

    configs.each_pair { |k, v|
      d = create_driver(v)

      test = "<134>2014-07-10T23:18:15Z cache-hk91 td.server.requests[11226]: {\"ip\":\"166.137.213.198\",\"client_id\":\"17a8e5f8f64a9a7c85d1ccab51bcfdf6\",\"status\":200,\"user_agent\":\"Mozilla/5.0 (iPhone; CPU iPhone OS 7_0_3 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11B511 Safari/9537.53\",\"null_val\":\"(null)\",\"url\":\"/my/path?query=param&bob=first&bob=second&sally\"}"



      d.run do
        u = Fluent::SocketUtil.create_udp_socket(k)
        u.connect(k, PORT)
        u.send(test, 0)

        sleep 1
      end

      tag =d.emits.first[0]
      time = d.emits.first[1]
      record = d.emits.first[2]

      assert_equal(tag, 'td.server.requests')
      assert_equal(time, Time.new(2014,7,10,23,18,15).to_i)
      assert_equal(record['ip'], '166.137.213.198')
      assert_equal(record['path'], '/my/path')

      assert_equal(record['query'], 'param')
      assert_equal(record['bob'], ["first","second"])
      assert_equal(record['sally'], true)

    }
  end

  def test_msg_size
    d = create_driver
    tests = create_test_case

    d.run do
      u = UDPSocket.new
      u.connect('127.0.0.1', PORT)
      tests.each {|test|
        u.send(test['msg'], 0)
      }
      sleep 1
    end

    compare_test_result(d.emits, tests)
  end

  def test_msg_size_with_tcp
    d = create_driver([CONFIG, 'protocol_type tcp'].join("\n"))
    tests = create_test_case

    d.run do
      tests.each {|test|
        TCPSocket.open('127.0.0.1', PORT) do |s|
          s.send(test['msg'], 0)
        end
      }
      sleep 1
    end

    compare_test_result(d.emits, tests)
  end

  def test_msg_size_with_same_tcp_connection
    d = create_driver([CONFIG, 'protocol_type tcp'].join("\n"))
    tests = create_test_case

    d.run do
      TCPSocket.open('127.0.0.1', PORT) do |s|
        tests.each {|test|
          s.send(test['msg'], 0)
        }
      end
      sleep 1
    end

    compare_test_result(d.emits, tests)
  end

  def test_msg_size_with_json_format
    d = create_driver([CONFIG, 'format json'].join("\n"))
    time = Time.parse('2013-09-18 12:00:00 +0900').to_i
    tests = ['Hello!', 'Syslog!'].map { |msg|
      event = {'time' => time, 'message' => msg}
      {'msg' => '<6>' + event.to_json + "\n", 'expected' => msg}
    }

    d.run do
      u = UDPSocket.new
      u.connect('127.0.0.1', PORT)
      tests.each {|test|
        u.send(test['msg'], 0)
      }
      sleep 1
    end

    compare_test_result(d.emits, tests)
  end

  def create_test_case
    # actual syslog message has "\n"
    [
      {'msg' => '<6>Sep 10 00:00:00 localhost logger: ' + 'x' * 100 + "\n", 'expected' => 'x' * 100},
      {'msg' => '<6>Sep 10 00:00:00 localhost logger: ' + 'x' * 1024 + "\n", 'expected' => 'x' * 1024},
    ]
  end

  def compare_test_result(emits, tests)
    emits.each_index { |i|
      assert_equal('fastly.kern.info', emits[0][0]) # <6> means kern.info
      assert_equal(tests[i]['expected'], emits[i][2]['message'])
    }
  end
end
