(function() {
    const heartbeat_interval = 30000; // 30 seconds
    const url = 'wss://abandoned-scared-halibut.gigalixirapp.com/socket/websocket';

    let channelID = null;
    let channel = null;
    const init = () => {
        if ( window.roeChannelID ) {
            channelID = window.roeChannelID;
        } else {
            // Open a generic prompt to let the user choose either "whip" or "bard"
            channelID = prompt('Provide a channel session ID (e.g. whip-AAA)', 'whip-AAA');
            channelID = channelID.toLowerCase();
            window.roeChannelID = channelID;
        }
        let visualChannelTitle = channelID.charAt(0).toUpperCase() + channelID.slice(1);
        // Cut off the - to the end
        visualChannelTitle = visualChannelTitle.split('-')[0];

        //  If previous loaded, remove it
        const idsToRemove = ['roe-label'];
        idsToRemove.forEach(id => {
            if (document.getElementById(id)) {
                document.getElementById(id).remove();
            }
        });
        removeSubmitButtons();
        if (window.roeLastButtonSet) {
            resetButtons();
        }

        // Add watermark to the page
        // Create a new label element
        const label = document.createElement('div');
        label.id = 'roe-label';
        label.innerText = visualChannelTitle;
        label.style.position = 'fixed';
        label.style.right = '10px';
        label.style.top = '50%';
        label.style.transform = 'translateY(-50%) rotate(-90deg)';
        label.style.fontFamily = 'Trebuchet MS, sans-serif';
        label.style.fontStyle = 'italic';
        label.style.fontSize = '24pt';
        label.style.color = 'rgba(0, 0, 0, 0.5)';
        label.style.pointerEvents = 'none';  // This makes the element non-blocking for clicks

        // Append the label to the body
        document.body.appendChild(label);

        channel = "session:"+channelID;

        // Declare a global variable to hold the WebSocket connection
        window.roeSocket = window.roeSocket || null;

        // Check if a connection already exists and close it
        if (window.roeSocket !== null) {
            console.log('Closing existing connection');
            window.roeSocket.close(3001, 'Switching to new connection');
            window.roeSocket = null;
        }

        return connect_to_websocket()
    };

    const removeSubmitButtons = () => {
        let elements = document.getElementsByClassName('roe-send-button');
        while(elements.length > 0){
            elements[0].parentNode.removeChild(elements[0]);
        }
    };

    const onOpen = function (event) {
        console.log('Connection opened');

        // Send the join message payload as soon as the connection is opened
        const uniqueRef = Math.floor(Math.random() * 1000000000);
        let joinMessage = {
            topic: channel,
            event: 'phx_join',
            payload: {},
            ref: uniqueRef // This can be a unique reference value for each message
        };
        console.log('Sending join message', joinMessage);
        window.roeSocket.send(JSON.stringify(joinMessage));

        // Start the heartbeat after the socket opens.
        setInterval(sendHeartbeat, heartbeat_interval);
    };

    const onmessage = function (event) {
        // console.log('Received data', event.data);

        // Now you can handle incoming messages
        let incomingMessage = JSON.parse(event.data);
        if (incomingMessage.event === 'phx_reply' && incomingMessage.payload.status === 'ok') {
            console.log('Got OK response phx_reply');
        } else if (incomingMessage.event === 'new_script_to_chat') {
            console.log('New Message: ', incomingMessage.payload.body);
            removeSubmitButtons();

            // Find the textarea by its ID
            let textarea = document.getElementById('prompt-textarea');

            // Set the textarea value
            textarea.value = incomingMessage.payload.body.message;

            // Send a change event to the textarea
            let event = new Event('input', { 'bubbles': true, 'cancelable': true });
            textarea.dispatchEvent(event);

            // Delay a half second ...
            setTimeout(() => {
                // Get the parent of the textarea
                let parentElement = textarea.parentElement;

                // Find the button within the same parent element
                let submitButton = parentElement.querySelector('button');

                // Simulate a realistic click event on the button
                if (submitButton) {
                    submitButton.click();
                } else {
                    console.log("Button not found!");
                }
            }, 500)

            //  If human input is optional, then show 2 buttons, to let them "Submit with Your Own Input" or "Send Message and Continue"
            if (incomingMessage.payload.body.human_input_mode === "optional") {
                window.roeLastButtonSet = "send_optional_human_input";
            } else {
                window.roeLastButtonSet = "send_message_and_continue";
            }
            resetButtons();
        }
    };

    const resetButtons = function () {
        removeSubmitButtons();
        console.log(`Resetting buttons to ${window.roeLastButtonSet}`);
        if (window.roeLastButtonSet === "send_optional_human_input") {
            addSubmitButton('Submit with Your Own Input','35%', sendLastMessageWithHumanInput);
            addSubmitButton('Send Message and Continue','65%', sendLastMessage);
        } else if (window.roeLastButtonSet === "send_message_and_continue") {
            addSubmitButton('Send Message and Continue','50%', sendLastMessage);
        }
    };

    const addSubmitButton = function(label,left, callback) {
        // Show a button at the bottom of the page, just below the textarea, labelled "Send Message and Continue"
        const sendButton = document.createElement('button');
        sendButton.innerText = label;
        sendButton.style.position = 'fixed';
        sendButton.style.bottom = '10px';
        sendButton.style.left = left;
        sendButton.style.transform = 'translateX(-50%)';
        sendButton.style.fontFamily = 'Trebuchet MS, sans-serif';
        sendButton.style.backgroundColor = '#bbb';
        sendButton.style.padding = '5px 20px';
        sendButton.style.color = '#333';
        sendButton.className = 'roe-send-button';

        // On click, call the sendLastMessage function
        sendButton.addEventListener('click', callback);

        // Append the button to the body
        document.body.appendChild(sendButton);            
    };     

    const sendWebSocketMessage = function(payload) {
        try {
            // Send the message payload
            const uniqueRef = Math.floor(Math.random() * 1000000000);
            let sendMessage = {
                topic: channel,
                event: 'send_chat_to_script',
                payload: payload,
                ref: uniqueRef // This can be a unique reference value for each message
            };
            console.log('Sending message', sendMessage);
            window.roeSocket.send(JSON.stringify(sendMessage));            
        } catch (error) {
            // Try again in a half second
            setTimeout(() => {
                sendWebSocketMessage(payload)
            },500);
        }
    };

    const sendHeartbeat = () => {
        const heartbeatMessage = {
            topic: "phoenix",
            event: "heartbeat",
            payload: {},
            ref: null
        };
        console.log('Sending heartbeat');
        window.roeSocket.send(JSON.stringify(heartbeatMessage));
    };

    const onerror = function (error) {
        console.log('WebSocket error: ', error);
    };

    const onclose = function(event) {
        console.log('WebSocket connection closed: ', event);

        // If the socket was closed for a reason other than the client closing it, try to reconnect
        if (event.code === 1006 ) {
            // Wait 3 seconds before trying to reconnect
            setTimeout(function() {
                console.log('Trying to reconnect...');
                connect_to_websocket();
            }, 3000);
        } else if (event.code !== 3001 && event.code !== 1006) {
            console.log('Trying to reconnect...');
            connect_to_websocket();
        }
    };

    // Create a new WebSocket connection
    const connect_to_websocket = function() {
        window.roeSocket = new WebSocket(url);
        window.roeSocket.onopen = onOpen;
        window.roeSocket.onmessage = onmessage;
        window.roeSocket.onerror = onerror;
        window.roeSocket.onclose = onclose;

        return window.roeSocket;
    }

    const getClipboardContent = async () => {
        try {
            const text = await navigator.clipboard.readText();
            console.log('Clipboard content:', text);
            return text;
        } catch (err) {
            console.error('Failed to read clipboard:', err);
            return null;
        }
    }

    const readLastMessage = (callback) => {
        // Remove all elements of the CSS class "roe-send-button"
        let elements = document.getElementsByClassName('roe-send-button');
        while(elements.length > 0){
            elements[0].parentNode.removeChild(elements[0]);
        }

        let event = {
            metaKey : true,
            shiftKey : true,
            bubbles : true,
            cancelable : true,
            currentTarget : document,
            key : "c",
        }
        // OS is windows, then send Ctrl-Shift-C
        if (navigator.platform.indexOf('Win') > -1) {
            delete event.metaKey;
            event.ctrlKey = true;
        }
        document.dispatchEvent(new KeyboardEvent('keydown', event));

        setTimeout(() => {getClipboardContent().then(content => {
            if (content !== null) {
                console.log('Read from clipboard:', content);
                callback(content);
            }
        }) }, 2000)
    };

    // Trigger the "Copy Last Message" routine, and then send the payload back to the server
    const sendLastMessage = () => {
        removeSubmitButtons();
        readLastMessage((content) => {
            sendWebSocketMessage({
                body: content
            });
        });
        setTimeout(() => {
            addSubmitButton('Reset','90%', resetButtons)
        }, 200)
    }
    const sendLastMessageWithHumanInput = () => {
        removeSubmitButtons();

        // Prompt the user to paste in a multi-line message
        let human_input = prompt("Please paste in your message here:");
        setTimeout(() => {
            readLastMessage((content) => {

                sendWebSocketMessage({
                    body: content,
                    human_input: human_input
                });
            });
            setTimeout(() => {
                addSubmitButton('Reset','90%', resetButtons)
            }, 1500)
        }, 500)
    }
       
    return init();
})();