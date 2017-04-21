###
# Copyright (C) 2014-2017 Andrey Antukh <niwi@niwi.nz>
# Copyright (C) 2014-2017 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014-2017 David Barragán Merino <bameda@dbarragan.com>
# Copyright (C) 2014-2017 Alejandro Alonso <alejandro.alonso@kaleidos.net>
# Copyright (C) 2014-2017 Juan Francisco Alcántara <juanfran.alcantara@kaleidos.net>
# Copyright (C) 2014-2017 Xavi Julian <xavier.julian@kaleidos.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/auth.coffee
###

taiga = @.taiga
debounce = @.taiga.debounce

module = angular.module("taigaAuth", ["taigaResources"])

class LoginPage
    @.$inject = [
        'tgCurrentUserService',
        '$location',
        '$tgNavUrls',
        '$routeParams',
        '$tgAuth',
        '$tgConfig',
        '$window'
    ]
    # {}
    constructor: (currentUserService, $location, $navUrls, $routeParams, $auth, $config, $window) ->
        if currentUserService.isAuthenticated()
            if not $routeParams['force_login']
                url = $navUrls.resolve("home")
                if $routeParams['next']
                    url = decodeURIComponent($routeParams['next'])
                    $location.search('next', null)

                if $routeParams['unauthorized']
                    $auth.clear()
                    $auth.removeToken()
                else
                    $location.url(url)

module.controller('LoginPage', LoginPage)

class LogoutPage
    @.$inject = [
        'tgCurrentUserService',
        '$location',
        '$routeParams',
        '$tgAuth',
        '$tgConfig',
        '$window'
    ]
    # {}
    constructor: (currentUserService, $location, $routeParams, $auth, $config, $window) ->
        $auth.clear()
        $auth.removeToken()
        $window.location.href = $config.get("yapUrl") + "/auth/login"

module.controller('LogoutPage', LogoutPage)

#############################################################################
## Authentication Service
#############################################################################

class AuthService extends taiga.Service
    # {}
    @.$inject = ["$rootScope",
                 "$tgStorage",
                 "$tgModel",
                 "$tgResources",
                 "$tgHttp",
                 "$tgUrls",
                 "$tgConfig",
                 "$translate",
                 "tgCurrentUserService",
                 "tgThemeService"]

    constructor: (@rootscope, @storage, @model, @rs, @http, @urls, @config, @translate, @currentUserService,
                  @themeService) ->
        super()

        userModel = @.getUser()
        @._currentTheme = @._getUserTheme()

        @.setUserdata(userModel)

    setUserdata: (userModel) ->
        if userModel
            @.userData = Immutable.fromJS(userModel.getAttrs())
            @currentUserService.setUser(@.userData)
        else
            @.userData = null

    _getUserTheme: ->
        return @rootscope.user?.theme || @config.get("defaultTheme") || "taiga" # load on index.jade

    _setTheme: ->
        newTheme = @._getUserTheme()

        if @._currentTheme != newTheme
            @._currentTheme = newTheme
            @themeService.use(@._currentTheme)

    _setLocales: ->
        lang = @rootscope.user?.lang || @config.get("defaultLanguage") || "en"
        @translate.preferredLanguage(lang)  # Needed for calls to the api in the correct language
        @translate.use(lang)                # Needed for change the interface in runtime

    getUser: ->
        if @rootscope.user
            return @rootscope.user

        userData = @storage.get("userInfo")

        if userData
            user = @model.make_model("users", userData)
            @rootscope.user = user
            @._setLocales()

            @._setTheme()

            return user
        else
            @._setTheme()

        return null

    setUser: (user) ->
        @rootscope.auth = user
        @storage.set("userInfo", user.getAttrs())
        @rootscope.user = user

        @.setUserdata(user)

        @._setLocales()
        @._setTheme()

    clear: ->
        @rootscope.auth = null
        @rootscope.user = null
        @storage.remove("userInfo")

    setToken: (token) ->
        @storage.set("token", token)

    getToken: ->
        return @storage.get("token")

    removeToken: ->
        @storage.remove("token")

    isAuthenticated: ->
        if @.getUser() != null
            return true
        return false

    ## Http interface
    refresh: () ->
        url = @urls.resolve("user-me")

        return @http.get(url).then (data, status) =>
            user = data.data
            user.token = @.getUser().auth_token

            user = @model.make_model("users", user)

            @.setUser(user)
            return user

    # login: (data, type) ->
    #     url = @urls.resolve("auth")

    #     data = _.clone(data, false)
    #     data.type = if type then type else "normal"

    #     @.removeToken()

    #     return @http.post(url, data).then (data, status) =>
    #         user = @model.make_model("users", data.data)
    #         @.setToken(user.auth_token)
    #         @.setUser(user)
    #         return user

    loginByToken: (token) ->
        url = @urls.resolve("user-me")
        @.removeToken()
        @.clear()
        @currentUserService.removeUser()
        @.setToken(token)

        return @http.get(url).then (data, status) =>
            user = @model.make_model("users", data.data)
            @.setUser(user)
            return user

    logout: ->
        token = @.getToken()
        @.removeToken()
        @.clear()
        @currentUserService.removeUser()

        @._setTheme()
        @._setLocales()
        return token

    # register: (data, type, existing) ->
    #     url = @urls.resolve("auth-register")

    #     data = _.clone(data, false)
    #     data.type = if type then type else "public"
    #     if type == "private"
    #         data.existing = if existing then existing else false

    #     @.removeToken()

    #     return @http.post(url, data).then (response) =>
    #         user = @model.make_model("users", response.data)
    #         @.setToken(user.auth_token)
    #         @.setUser(user)
    #         return user

    # getInvitation: (token) ->
    #     return @rs.invitations.get(token)

    # acceptInvitiationWithNewUser: (data) ->
    #     return @.register(data, "private", false)

    # forgotPassword: (data) ->
    #     url = @urls.resolve("users-password-recovery")
    #     data = _.clone(data, false)
    #     @.removeToken()
    #     return @http.post(url, data)

    # changePasswordFromRecovery: (data) ->
    #     url = @urls.resolve("users-change-password-from-recovery")
    #     data = _.clone(data, false)
    #     @.removeToken()
    #     return @http.post(url, data)

    # changeEmail: (data) ->
    #     url = @urls.resolve("users-change-email")
    #     data = _.clone(data, false)
    #     return @http.post(url, data)

    # cancelAccount: (data) ->
    #     url = @urls.resolve("users-cancel-account")
    #     data = _.clone(data, false)
    #     return @http.post(url, data)

module.service("$tgAuth", AuthService)


#############################################################################
## Login Directive
#############################################################################

# Directive that manages the visualization of public register
# message link on login page
##\{nextUrl}


LoginDirective = ($auth, $location, $config, $routeParams, $navUrls, $window) ->
    link = ($scope) ->
        if $routeParams['next'] and $routeParams['next'] != $navUrls.resolve("login")
            $scope.nextUrl = decodeURIComponent($routeParams['next'])
        else
            $scope.nextUrl = $navUrls.resolve("home")

        onSuccess = (response) ->
            # $events.setupConnection()
            if $scope.nextUrl.indexOf('http') == 0
                $window.location.href = $scope.nextUrl
            else
                $location.url($scope.nextUrl)

        onError = (response) ->
            $auth.removeToken()
            $auth.clear()
            $location.url($scope.nextUrl)

        if $routeParams.token?
            promise = $auth.loginByToken($routeParams.token)
            return promise.then(onSuccess, onError)
        else
            $window.location.href = $config.get("yapUrl") + "/auth/login/taiga?next=discover"
        

    return {link:link}

module.directive("tgLogin", ["$tgAuth", "$tgLocation", "$tgConfig", "$routeParams",
                             "$tgNavUrls", "$window", LoginDirective])

