# frozen_string_literal: true

require 'net/http'

module ElasticAPM
  RSpec.describe 'Spy: NetHTTP', :intercept do
    after { WebMock.reset! }

    it 'spans http calls' do
      WebMock.stub_request(:get, %r{http://example.com/.*})

      with_agent do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.start('example.com') do |http|
            http.get '/'
          end
        end
      end

      span, = @intercepted.spans

      expect(span.name).to eq 'GET example.com'
    end

    it 'spans inline http calls' do
      WebMock.stub_request(:get, %r{http://example.com/.*})

      with_agent do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.get('example.com', '/index.html')
        end
      end

      span, = @intercepted.spans

      expect(span.name).to eq 'GET example.com'
    end

    it 'adds http context' do
      WebMock.stub_request(:get, %r{http://example.com/.*})

      with_agent do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.start('example.com') do |http|
            http.get '/page.html'
          end
        end
      end

      span, = @intercepted.spans

      http = span.context.http

      expect(http.url).to match('http://example.com/page.html')
      expect(http.method).to match('GET')
      expect(http.status_code).to match('200')
    end

    it 'adds both TraceContext headers' do
      req_stub =
        WebMock.stub_request(:get, %r{http://example.com/.*}).with do |req|
          header = req.headers['Traceparent']
          expect(header).to_not be nil
          expect(req.headers['Elastic-Apm-Traceparent']).to_not be nil
          expect { TraceContext.parse(header) }.to_not raise_error
        end

      with_agent do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.start('example.com') do |http|
            http.get '/'
          end
        end
      end

      expect(req_stub).to have_been_requested
    end

    it 'adds traceparent header with no span' do
      req_stub = WebMock.stub_request(:get, %r{http://example.com/.*})

      with_agent transaction_max_spans: 0 do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.start('example.com') do |http|
            http.get '/'
          end
        end
      end

      expect(req_stub).to have_been_requested
    end

    it 'skips prefixed traceparent header when disabled' do
      req_stub =
        WebMock.stub_request(:get, %r{http://example.com/.*}).with do |req|
          expect(req.headers['Elastic-Apm-Traceparent']).to be nil
          expect(req.headers['Traceparent']).to_not be nil
        end

      with_agent(use_elastic_traceparent_header: false) do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.start('example.com') do |http|
            http.get '/'
          end
        end
      end

      expect(req_stub).to have_been_requested
    end

    it 'can be disabled' do
      WebMock.stub_request(:any, %r{http://example.com/.*})

      with_agent do
        expect(ElasticAPM::Spies::NetHTTPSpy).to_not be_disabled

        ElasticAPM.with_transaction 'Net::HTTP test' do
          ElasticAPM::Spies::NetHTTPSpy.disable_in do
            Net::HTTP.start('example.com') do |http|
              http.get '/'
            end
          end

          Net::HTTP.start('example.com') do |http|
            http.post '/', 'a=1'
          end
        end
      end

      expect(@intercepted.transactions.length).to be 1
      expect(@intercepted.spans.length).to be 1

      span, = @intercepted.spans
      expect(span.name).to eq 'POST example.com'
      expect(span.type).to eq 'ext'
      expect(span.subtype).to eq 'net_http'
      expect(span.action).to eq 'POST'

      ElasticAPM.stop
      WebMock.reset!
    end

    describe 'destination info' do
      it 'adds to span context' do
        WebMock.stub_request(:get, %r{http://example.com:1234/.*})

        with_agent do
          ElasticAPM.with_transaction 'Net::HTTP test' do
            Net::HTTP.start('example.com', 1234) do |http|
              http.get '/some/path?a=1'
            end
          end
        end

        span, = @intercepted.spans

        expect(span.context.destination.name).to eq 'http://example.com:1234'
        expect(span.context.destination.resource).to eq 'example.com:1234'
        expect(span.context.destination.type).to eq 'external'
      end
    end

    it 'handles IPv6 addresses' do
      WebMock.stub_request(:get, %r{http://\[::1\]/.*})

      with_agent do
        ElasticAPM.with_transaction 'Net::HTTP test' do
          Net::HTTP.start('[::1]') do |http|
            http.get '/path'
          end
        end
      end

      span, = @intercepted.spans

      expect(span.name).to eq 'GET [::1]'
      expect(span.context.destination.name).to eq 'http://[::1]'
      expect(span.context.destination.resource).to eq '[::1]:80'
      expect(span.context.destination.type).to eq 'external'
    end
  end
end
