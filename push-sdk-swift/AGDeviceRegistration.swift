/*
* JBoss, Home of Professional Open Source.
* Copyright Red Hat, Inc., and individual contributors
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import Foundation

/**
 * Utility to register an iOS device with the AeroGear UnifiedPush Server.
 */
class AGDeviceRegistration: NSObject, NSURLSessionTaskDelegate {
    
    struct AGDeviceRegistrationError {
        static let AGPushErrorDomain = "AGPushErrorDomain"
        static let AGNetworkingOperationFailingURLRequestErrorKey = "AGNetworkingOperationFailingURLRequestErrorKey"
        static let AGNetworkingOperationFailingURLResponseErrorKey = "AGNetworkingOperationFailingURLResponseErrorKey"
    }
    
    var serverURL: NSURL?
    var session: NSURLSession?
    
    init(serverURL: NSURL) {
        super.init()

        self.serverURL = serverURL;

        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        self.session = NSURLSession(configuration: sessionConfig, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
    }
    
    func registerWithClientInfo(clientInfo: ((config: AGClientDeviceInformation) -> Void)!,
        success:(() -> Void)!, failure:((NSError) -> Void)!) -> Void {
            
            let clientInfoObject = AGClientDeviceInformationImpl()
        
            clientInfo(config: clientInfoObject)
        
            assert(clientInfoObject.deviceToken, "'token' should be set")
            assert(clientInfoObject.variantID, "'variantID' should be set")
            assert(clientInfoObject.variantSecret, "'variantSecret' should be set");
            
            // set up our request
            let request = NSMutableURLRequest(URL: serverURL!.URLByAppendingPathComponent("/rest/registry/device"))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.HTTPMethod = "POST"
            
            // apply HTTP Basic
            let basicAuthCredentials = "\(clientInfoObject.variantID):\(clientInfoObject.variantSecret)" .dataUsingEncoding(          NSUTF8StringEncoding)
            let base64Encoded = basicAuthCredentials.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.fromRaw(0)!)
            
            request.setValue("Basic \(base64Encoded)", forHTTPHeaderField: "Authorization")
            
            // serialize request
            let postData = NSJSONSerialization.dataWithJSONObject(clientInfoObject.extractValues(), options: NSJSONWritingOptions.fromMask(0), error: nil)
            
            request.HTTPBody = postData
            
            let task = session!.dataTaskWithRequest(request,
                completionHandler: {(data, response, error) in
                    if error {
                        failure(error)
                        return
                    }
                    
                    // verity HTTP status
                    let httpResp = response as NSHTTPURLResponse

                    // did we succeed?
                    if httpResp.statusCode == 200 {
                        success()

                    } else { // nope, client request error (e.g. 401 /* Unauthorized */)
                        let userInfo = [NSLocalizedDescriptionKey : NSHTTPURLResponse.localizedStringForStatusCode(httpResp.statusCode),
                            AGDeviceRegistrationError.AGNetworkingOperationFailingURLRequestErrorKey: request,
                            AGDeviceRegistrationError.AGNetworkingOperationFailingURLResponseErrorKey: response];
                        
                        let error = NSError(domain:AGDeviceRegistrationError.AGPushErrorDomain, code: NSURLErrorBadServerResponse, userInfo: userInfo)

                        failure(error)
                    }
            })
            
            task.resume()
    }
    
    /*
    // we need to cater for possible redirection
    //
    // NOTE:
    //      As per Apple doc, the passed req is 'the proposed redirected request'. But we cannot return it as it is. The reason is,
    //      user-agents (and in our case NSURLconnection) 'erroneous' after a 302-redirection modify the request's http method
    //      and sets it to GET if the client initially performed a POST (as we do here).
    //
    //      See  RFC 2616 (section 10.3.3) http://www.ietf.org/rfc/rfc2616.txt
    //      and related blog: http://tewha.net/2012/05/handling-302303-redirects/
    //
    //      We need to 'override' that 'default' behaviour to return the original attempted NSURLRequest
    //      with the URL parameter updated to point to the new 'Location' header.
    //
    */
    func URLSession(session: NSURLSession!, task: NSURLSessionTask!, willPerformHTTPRedirection redirectResponse: NSHTTPURLResponse!, newRequest redirectReq: NSURLRequest!, completionHandler: ((NSURLRequest!) -> Void)!) {
        
        var request = redirectReq;
        
        if redirectResponse { // we need to redirect
            // update URL of the original request
            // to the 'new' redirected one
            var origRequest = task.originalRequest .mutableCopy() as NSMutableURLRequest
            origRequest.URL = redirectReq.URL
            request = origRequest
        }
        
        completionHandler(request)
    }
}
