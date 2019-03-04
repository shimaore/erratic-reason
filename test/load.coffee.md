    (require 'chai').should()

    describe 'The module', ->
      it 'should load', ->
        require '../server'

    describe 'Monitor', ->
      it 'should return a function', ->
        (require '../monitor').should.be.a 'function'
