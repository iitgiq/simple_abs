require "simple_abs/version"

module SimpleAbs

  # Here, we are facing three different scenarios
  # 1. First time to see this test. Create cookie, create record.
  # 2. Seen this before. Update the record with more impressions.
  # 3. Already marked as converted. Skip and return the choice
  def ab_test_impression(name, tests, impression: 1)
    ab_test_name = ('ab_test_' + name).to_sym

    # First the override. This is for test purposes
    return params[ab_test_name] if params[ab_test_name].present?

    if browser.bot?
      test_value = tests[rand(tests.size)]
      return test_value
    end

    # Now check if cookie exists
    test_json = ab_test_read_cookie(ab_test_name)

    if !test_json
      test_value = tests[rand(tests.size)]
      test_record = AbTest.create!(experiment: name, choice: test_value, impression: impression)
      ab_test_save_cookie(ab_test_name, test_record)
    elsif !test_json[:finished]
      test_record = test_json[:id] && AbTest.find_by(id: test_json[:id], experiment: name)
      test_value = test_record.choice rescue test_json[:choice]
      test_record.increment!(:impression, impression) if test_record
      ab_test_save_cookie(ab_test_name, test_record) if test_record
    else # Converted, pull the current choice
      test_record = test_json[:id] && AbTest.find_by(id: test_json[:id], experiment: name)
      test_value = test_record.choice rescue test_json[:choice]
    end
    # In case if the test value is not one of the given ones, fall back to
    # a random one. Here we do not want to delete the db record and/or reset
    # the cookie. One common hacky usage is to force a choice by
    # ab_test_impression(name, ['mychoice']) but I don't want this kind of usage
    # to destroy db/cookie records
    test_value = tests[rand(tests.size)] unless tests.include?(test_value)

    return test_value
  end

  # For converted, we have three scenarios
  # 0. Not a participant, ignore
  # 1. Already converted, do nothing
  # 2. Conversion with no finish: Add 1/N to conversion, and tag time if first
  # 3. Conversion with finish: Do #2 and set cookie to be finished.
  def ab_test_converted!(name, conversion: 1, finished: true)
    if !browser.bot?
      ab_test_name = ('ab_test_' + name).to_sym
      test_json = ab_test_read_cookie(ab_test_name)
      if test_json && !test_json[:finished]
        test_record = test_json[:id] && AbTest.find_by(id: test_json[:id], experiment: name)
        return unless test_record # Without a record we should probably skip.
        test_record.increment!(:conversion, conversion)
        test_record.update_attribute(:converted_at, Time.now()) unless test_record.converted_at.present?
        if finished
          ab_test_save_cookie(ab_test_name, test_record, 'converted')
        else
          ab_test_save_cookie(ab_test_name, test_record)
        end
      end
    end
  end

  # For abort, we first pull the record, then we delete the db record.
  # Then we set the cookie to aborted. It has two results:
  # 1. The test will not touch db anymore
  # 2. The choice will therefore persist.
  def ab_test_aborted!(name)
    if !browser.bot?
      ab_test_name = ('ab_test_' + name).to_sym
      test_json = ab_test_read_cookie(ab_test_name)
      if test_json && test_json[:id]
        test_record = test_json[:id] && AbTest.find_by(id: test_json[:id], experiment: name)
        return unless test_record # Without a record we should probably skip.
        test_record.destroy if test_record
        ab_test_save_cookie(ab_test_name, test_record, 'aborted')
      end
    end
  end

  # This is similar to impression, only that it's not going to do anything
  # about the record. It will return default if given
  def ab_test_peek(name, default: nil)
    ab_test_name = ('ab_test_' + name).to_sym

    # First the override. This is for test purposes
    return params[ab_test_name] if params[ab_test_name].present?

    # Now check if cookie exists
    test_json = ab_test_read_cookie(ab_test_name)

    if !test_json
      # Do not initialize a test
      test_value = default
    elsif !test_json[:finished]
      test_record = test_json[:id] && AbTest.find_by(id: test_json[:id], experiment: name)
      test_value = test_record.choice rescue test_json[:choice]
      # No impression increment here as we are just peeking it
    else # Converted, pull the current choice
      test_record = test_json[:id] && AbTest.find_by(id: test_json[:id], experiment: name)
      test_value = test_record.choice rescue test_json[:choice]
      # No operation here as we are just peeking
    end

    return test_value
  end

  def ab_test_status(name)
    ab_test_name = ('ab_test_' + name).to_sym

    # Now check if cookie exists
    test_json = ab_test_read_cookie(ab_test_name)

    if !test_json
      return 'none'
    elsif !test_json[:finished]
      return 'running'
    else # Converted, pull the current choice. Either aborted or converted
      return test_json[:finished]
    end
  end

  def ab_test_save_cookie(ab_test_name, test_record, finished = nil)
    cookies.permanent[ab_test_name] = test_record.cookie_string(finished)
  end
  # Load the data from the cookie. Simply parse the cookie as a hash
  def ab_test_read_cookie(ab_test_name)
    JSON.parse(cookies[ab_test_name]).with_indifferent_access rescue nil
  end

  class Railtie < Rails::Railtie
    initializer "simple_abs.initialize" do
      ActionView::Base.send :include, SimpleAbs
      ActionController::Base.send :include, SimpleAbs
    end
  end

  class AbTest < ActiveRecord::Base
    attr_accessible :experiment, :choice, :impression, :conversion, :converted_at
    def cookie_string(finished = nil)
      json = self.as_json(:only => [:id, :experiment, :choice, :impression, :conversion])
      json['finished'] = finished if finished
      JSON.generate(json)
    end
  end
end
