# Copyright (c) Microsoft Open Technologies, Inc. All rights reserved. See License.txt in the project root for license information.

require 'thread'

module RX
    class Scheduler

        # Schedules an action to be executed.
        def schedule(action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_with_state(action, lambda { |sched, fn| RX::Scheduler.invoke(sched, fn) })
        end

        # Schedules an action to be executed after the specified relative due time.
        def schedule_relative(due_time, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_relative_with_state(action, due_time, lambda { |sched, fn| RX::Scheduler.invoke(sched, fn) })
        end

        # Schedules an action to be executed at the specified absolute due time.
        def schedule_absolute(due_time, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_absolute_with_state(action, due_time, lambda { |sched, fn| RX::Scheduler.invoke(sched, fn) })
        end

        # Schedules an action to be executed recursively.
        def schedule_recursive(action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_recursive_with_state(action, lambda {|_action, _self| _action(lambda { _self(_action) }) })
        end

        # Schedules an action to be executed recursively.
        def schedule_recursive_with_state(state, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_with_state({ :state => state, :action => action}, lambda { |sched, pair| RX::Scheduler.invoke_recursive(sched, pair) })
        end

        # Schedules an action to be executed recursively after a specified relative due time.
        def schedule_recursive_relative(due_time, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_recursive_relative_with_state(action, due_time, lambda {|_action, _self| _action(lambda {|dt| _self(_action, dt) }) })
        end

        # Schedules an action to be executed recursively after a specified relative due time.
        def schedule_recursive_relative_with_state(state, due_time, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_relative_with_state(
                { :state => state, :action => action}, 
                due_time,
                lambda { |sched, pair| RX::Scheduler.invoke_recursive_time(sched, pair, 'schedule_relative_with_state') }
            )
        end

        # Schedules an action to be executed recursively after a specified absolute due time.
        def schedule_recursive_absolute(due_time, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_absolute_relative_with_state(action, due_time, lambda {|_action, _self| _action(lambda {|dt| _self(_action, dt) }) })
        end

        # Schedules an action to be executed recursively after a specified absolute due time.
        def schedule_recursive_absolute_with_state(state, due_time, action)
            raise ArgumentError.new 'action cannot be nil' if action.nil?
            self.schedule_absolute_with_state(
                { :state => state, :action => action}, 
                due_time,
                lambda { |sched, pair| RX::Scheduler.invoke_recursive_time(sched, pair, 'schedule_absolute_with_state') }
            )
        end

        # Normalizes the specified TimeSpan value to a positive value.
        def self.normalize(time_span)
            time_span < 0 ? 0 : time_span
        end

        private

        def self.invoke(scheduler, action)
            action.call()
            RX::Disposable.empty
        end

        def self.invoke_recursive(scheduler, pair)
            group = RX::CompositeDisposable.new
            gate = Mutex.new
            state = pair[:state]
            action = pair[:action]

            recursive_action = lambda {|state1|
                action.call(state, lambda { |state2|  
                    is_added = false
                    is_done = false
                    d = scheduler.schedule_with_state(state2, lambda { |scheduler1, state3| 
                        @gate.synchronize do
                            if is_added
                                group.delete(d)
                            else
                                is_done = true
                            end
                        end

                        recursive_action.call(state3)
                        return RX::Disposable.empty
                    })

                    @gate.synchronize do
                        unless is_done
                            group.push(d)
                            is_added = true
                        end
                    end
                })
            }

            recursive_action.call(state)
            return group
        end

        def invoke_recursive_time(scheduler, pair, method)
            group = RX::CompositeDisposable.new
            gate = Mutex.new
            state = pair[:state]
            action = pair[:action]

            recursive_action = lambda { |state1|
                action.call(state1, lambda { |state2, due_time1|
                    is_added = false
                    is_done = false

                    d = scheduler.send(method, state2, due_time1, lambda { |scheduler1, state3|
                        @gate.synchronize do
                            if is_added
                                group.delete(d)
                            else
                                is_done = true
                            end
                        end
                        recursive_action.call(state3)
                        return RX::Disposable.empty
                    })

                    @gate.synchronize do
                        unless is_done
                            group.push(d)
                            is_added = true
                        end
                    end
                })
            }

            recursive_action.call(state)
            return group            
        end
    end
end