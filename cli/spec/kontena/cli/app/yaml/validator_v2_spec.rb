require_relative '../../../../spec_helper'
require 'kontena/cli/apps/yaml/validator_v2'

describe Kontena::Cli::Apps::YAML::ValidatorV2 do
  describe '#validate_keys' do
    it 'returns error on invalid key' do
      result = subject.validate_keys('name' => 'wordpress')
      expect(result['name'].size).to eq(1)
    end
  end

  describe '#validate_options' do
    context 'build' do
      it 'can be string' do
        result = subject.validate_options('build' => '.')
        expect(result.success?).to be_truthy
        expect(result.messages.key?('build')).to be_falsey
      end

      it 'can be hash' do
        result = subject.validate_options('build' => { 'context' => '.' })
        expect(result.success?).to be_truthy
        expect(result.messages.key?('build')).to be_falsey
      end

      it 'returns error if build is hash and context is missing' do
        result = subject.validate_options('build' => {})
        expect(result.success?).to be_falsey
        expect(result.messages.key?('build')).to be_truthy
      end

      it 'returns error if optional dockerfile is not string' do
        result = subject.validate_options('build' => {
          'context' => '.',
          'dockerfile' => 123
        })
        expect(result.success?).to be_falsey
        expect(result.messages.key?('build')).to be_truthy
      end
    end
    it 'validates image is string' do
      result = subject.validate_options('image' => true)
      expect(result.success?).to be_falsey
      expect(result.messages.key?('image')).to be_truthy
    end

    it 'validates stateful is boolean' do
      result = subject.validate_options('stateful' => 'bool')
      expect(result.messages.key?('stateful')).to be_truthy
    end

    it 'validates network_mode is host or bridge' do
      result = subject.validate_options('network_mode' => 'invalid')
      expect(result.messages.key?('network_mode')).to be_truthy

      result = subject.validate_options('network_mode' => 'bridge')
      expect(result.messages.key?('network_mode')).to be_falsey

      result = subject.validate_options('network_mode' => 'host')
      expect(result.messages.key?('network_mode')).to be_falsey
    end

    context 'affinity' do
      it 'is optional' do
        result = subject.validate_options({})
        expect(result.messages.key?('affinity')).to be_falsey
      end

      it 'must be array' do
        result = subject.validate_options('affinity' => 'node==node1')
        expect(result.messages.key?('affinity')).to be_truthy
        result = subject.validate_options('affinity' => ['node==node1'])
        expect(result.messages.key?('affinity')).to be_falsey
      end

      it 'validates format' do
        result = subject.validate_options('affinity' => ['node=node1'])
        expect(result.messages.key?('affinity')).to be_truthy

        result = subject.validate_options('affinity' => ['node==node1', 'service!=mariadb'])
        expect(result.messages.key?('affinity')).to be_falsey
      end
    end

    context 'command' do
      it 'is optional' do
        result = subject.validate_options({})
        expect(result.messages.key?('command')).to be_falsey
      end

      it 'must be string or empty' do
        result = subject.validate_options('command' => 1234)
        expect(result.messages.key?('command')).to be_truthy

        result = subject.validate_options('command' => nil)
        expect(result.messages.key?('command')).to be_falsey

        result = subject.validate_options('command' => 'bundle exec rails s')
        expect(result.messages.key?('command')).to be_falsey
      end
    end

    it 'validates cpu_shares is integer' do
      result = subject.validate_options('cpu_shares' => '1m')
      expect(result.messages.key?('cpu_shares')).to be_truthy
      result = subject.validate_options('cpu_shares' => 1024)
      expect(result.messages.key?('cpu_shares')).to be_falsey
      result = subject.validate_options({})
      expect(result.messages.key?('cpu_shares')).to be_falsey
    end

    it 'validates environment is array or hash' do
      result = subject.validate_options('environment' => 'KEY=VALUE')
      expect(result.messages.key?('environment')).to be_truthy
      result = subject.validate_options('environment' => ['KEY=VALUE'])
      expect(result.messages.key?('environment')).to be_falsey
      result = subject.validate_options('environment' => { 'KEY' => 'VALUE' })
      expect(result.messages.key?('environment')).to be_falsey
    end

    context 'validates secrets' do
      it 'must be array' do
        result = subject.validate_options('secrets' => {})
        expect(result.messages.key?('secrets')).to be_truthy
      end

      context 'item' do
        it 'must contain secret' do
          result = subject.validate_options('secrets' => [{ 'name' => 'test', 'type' => 'env' }])
          expect(result.messages.key?('secrets')).to be_truthy
        end

        it 'must contain name' do
          result = subject.validate_options('secrets' => [{ 'secret' => 'test', 'type' => 'env' }])
          expect(result.messages.key?('secrets')).to be_truthy
        end

        it 'must contain type' do
          result = subject.validate_options('secrets' => [{ 'secret' => 'test', 'name' => 'test' }])
          expect(result.messages.key?('secrets')).to be_truthy
        end

        it 'accepts valid input' do
          result = subject.validate_options('secrets' =>
            [
              {
                'secret' => 'test',
                'name' => 'test',
                'type' => 'env'
              }
            ])
          expect(result.messages.key?('secrets')).to be_falsey
        end
      end
    end

    context 'logging' do
      context 'options' do
        it 'must be hash' do
          result = subject.validate_options('logging' => { 'options' => [] })
          expect(result.messages.key?('logging')).to be_truthy
          data = {
            'logging' => {
              'options' => {
                  'syslog-address' => "tcp://192.168.0.42:123"
              }
            }
          }
          result = subject.validate_options(data)
          expect(result.messages.key?('logging')).to be_falsey
        end
      end
    end

    context 'hooks' do
      context 'validates pre_build' do
        it 'must be array' do
          result = subject.validate_options('hooks' => { 'pre_build' => {} })
          expect(result.messages.key?('hooks')).to be_truthy
          data = {
            'hooks' => {
              'pre_build' => [
                {
                  'cmd' => 'rake db:migrate'
                }
              ]
            }
          }
          result = subject.validate_options(data)
          expect(result.messages.key?('hooks')).to be_falsey
        end
      end
      context 'post_start' do
        it 'must be array' do
          result = subject.validate_options('hooks' => { 'post_start' => {} })
          expect(result.messages.key?('hooks')).to be_truthy
          data = {
            'hooks' => {
              'post_start' => [
                {
                  'name' => 'migrate',
                  'cmd' => 'rake db:migrate',
                  'instances' => '*'
                }
              ]
            }
          }
          result = subject.validate_options(data)
          expect(result.messages.key?('hooks')).to be_falsey
        end

        context 'item' do
          it 'must contain name' do
            result = subject.validate_options('hooks' =>
            {
              'post_start' => [
                {
                  'cmd' => 'rake db:migrate',
                  'instances' => '1'
                }
              ]
            })
            expect(result.messages.key?('hooks')).to be_truthy
          end

          it 'must contain cmd' do
            result = subject.validate_options('hooks' =>
            {
              'post_start' => [
                {
                  'name' => 'migrate',
                  'instances' => '1'
                }
              ]
            })
            expect(result.messages.key?('hooks')).to be_truthy
          end

          it 'must contain instance number or *' do
            result = subject.validate_options('hooks' =>
            {
              'post_start' => [
                { 'name' => 'migrate',
                  'cmd' => 'rake db:migrate'
                }
              ]
            })
            expect(result.messages.key?('hooks')).to be_truthy
            data = {
              'hooks' => {
                'post_start' => [
                  {
                    'name' => 'migrate',
                    'cmd' => 'rake db:migrate',
                    'instances' => 'all',
                    'oneshot' => true
                  }
                ]
              }
            }
            result = subject.validate_options(data)
            expect(result.messages.key?('hooks')).to be_truthy
          end

          it 'may contain boolean oneshot' do
            data = {
              'hooks' => {
                'post_start' => [
                  {
                    'name' => 'migrate',
                    'cmd' => 'rake db:migrate',
                    'instances' => '*',
                    'oneshot' => 'true'
                  }
                ]
              }
            }
            result = subject.validate_options(data)
            expect(result.messages.key?('hooks')).to be_truthy
          end
        end

        it 'validates depends_on is array' do
          result = subject.validate_options('depends_on' => 'web')
          expect(result.messages.key?('depends_on')).to be_truthy

          result = subject.validate_options('depends_on' => ['web'])
          expect(result.messages.key?('depends_on')).to be_falsey
        end

        it 'validates volumes is array' do
          result = subject.validate_options('volumes' => '/app')
          expect(result.messages.key?('volumes')).to be_truthy

          result = subject.validate_options('volumes' => ['/app'])
          expect(result.messages.key?('volumes')).to be_falsey
        end

        it 'validates volumes_from is array' do
          result = subject.validate_options('volumes_from' => 'mysql_data')
          expect(result.messages.key?('volumes_from')).to be_truthy

          result = subject.validate_options('volumes_from' => ['mysql_data'])
          expect(result.messages.key?('volumes_from')).to be_falsey
        end
      end
    end
  end
end
