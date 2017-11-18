SpreeShouter
============

Introduction goes here.

## Installation

1. Add this extension to your Gemfile with this line:
  ```ruby
  gem 'spree_shouter', path: 'PATH_TO_GEM'
  ```

2. Install the gem using Bundler:
  ```ruby
  bundle install
  ```

3. Install beanstalkd
  ```
  brew install beanstalkd
  ```

4. Run beanstalkd server
  ```
  beanstalkd -p 11300
  ```

5. Restart your server

## Testing

1. Install the Bundle:
  ```
  bundle install
  ```

2. Build dummy app:
  ```
  bundle exec rake test_app
  ```

3. Run the tests:
  ```
  bundle exec rake
  ```
