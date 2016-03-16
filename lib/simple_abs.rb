require "simple_abs/version"

module SimpleAbs

  # Here, we are facing three different scenarios
  # 1. First time to see this test. Create cookie, create record.
  # 2. Seen this before. Update the record with more impressions.
  # 3. Already marked as converted. Skip and return the choice
  def ab_test_impression(name, tests, impression: 1)
    if browser.bot?
      test_value = tests[rand(tests.size)]
      return test_value
    end

    ab_test_name = ('ab_test_' + name).to_sym

    # First the override. This is for test purposes
    return params[ab_test_name] if params[ab_test_name].present?

    # Now check of cookie exists
    test_json = JSON.parse(cookies[ab_test_name]) rescue nil

    if !test_json
      test_value = tests[rand(tests.size)]
      test_record = AbTest.create!(experiment: name, choice: test_value, impression: impression)
      cookies.permanent[ab_test_name] = test_record.cookie_string
    elsif !test_json[:finished]
      test_value = test_json[:choice]
      test_record = AbTest.find(test_json['id'])
      test_record.increment!(:impression, impression)
      cookies.permanent[ab_test_name] = test_record.cookie_string # To be deleted
    else # Converted
      test_value = test_json[:choice]
    end

    return test_value
  end

  # For converted, we have three scenarios
  # 0. Not a participant, ignore
  # 1. Already converted, do nothing
  # 2. Conversion with no finsih: Add 1/N to conversion, and tag time if first
  # 3. Conversion with finish: Do #2 and set cookie to be finished.
  def ab_test_converted!(name, conversion: 1, finished: true)
    if !browser.bot?
      ab_test_name = ('ab_test_' + name).to_sym
      test_json = JSON.parse(cookies[ab_test_name]) rescue nil
      if test_json && !test_json[:finished]
        test_record = AbTest.find(test_json['id'])
        test_record.increment!(:conversion, conversion)
        test_record.update_attribute(:converted_at, Time.now()) unless test_record.converted_at.present?
        if finished
          cookies.permanent[ab_test_name] = test_record.cookie_string('converted')
        else
          cookies.permanent[ab_test_name] = test_record.cookie_string # To be deleted
        end
      end
    end
  end

  def ab_test_aborted!(name)
    if !browser.bot?
      ab_test_name = ('ab_test_' + name).to_sym
      test_json = JSON.parse(cookies[ab_test_name]) rescue nil
      test_value = test_json
      if test_value && test_value[:id]
        test_record = AbTest.find(test_json[:id])
        test_record.destroy if test_record
        cookies.permanent[ab_test_name] = test_record.cookie_string('aborted')
      end
    end
  end

  def ab_test_save_cookie(test_record)
    cookies.permanent[test_record.experiment] = test_record.cookie_string
  end
  def ab_test_read_cookie
    test_json = JSON.parse(cookies[ab_test_name]) rescue nil
    test_json && AbTest.find_by_id(test_json['id'])
  end
  class AbTest < ActiveRecord::Base
    attr_accessible :experiment, :choice, :impression, :conversion, :converted_at
    def cookie_string(finished = nil)
      json = self.as_json(:only => [:id, :experiment, :choice, :impression, :conversion])
      json['finished'] = finished if finished
      JSON.generate(json)
    end
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
