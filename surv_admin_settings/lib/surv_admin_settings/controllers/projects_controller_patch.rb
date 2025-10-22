module SurvAdminSettings
  module Controllers
    module ProjectsControllerPatch
      def self.included(base)
        base.class_eval do
          alias_method :original_show, :show

          def show
            original_show
            # Удаляем вкладку "Действия" (activity) из списка вкладок, если список вкладок определён
            if instance_variable_defined?(:@tabs) && @tabs.is_a?(Array)
              @tabs.reject! { |tab| tab[:name].to_s == 'activity' }
            end
          end
        end
      end
    end
  end
end
