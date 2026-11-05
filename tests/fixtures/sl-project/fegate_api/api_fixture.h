/*==============================================================================
  api_fixture.h
==============================================================================*/
#include "defines.h"

namespace dbNode {

/**HELP_FUN
@decl
int dbNode::First()

@brief
Returns the first node index among all existing nodes

@return
int
First node index
*/
int First();

/**HELP_FUN
@decl
int dbNode::Next(int index)

@brief
Returns the next existing node index of the given node index

@in
int index
Previous node index

@return
int
Next node index
*/
int Next(int index);

}

/**HELP_FUN
@decl
bool xuFileOpenWindow(string title, string filterName, string filter, ref string fileName)

@brief
Opens a file selection dialog
*/
bool xuFileOpenWindow(string title, string filterName, string filter, ref string fileName);

/**HELP_FUN
@decl
int xutButton(string label, int option, functor callback)

@brief
Adds a button
*/
int xutButton(string label, int option, functor callback);

/**HELP_FUN
@decl
void xutPanel(string title)

@brief
Starts a panel
*/
void xutPanel(string title);

/**HELP_FUN
@decl
int xutText(string label, ref string value, functor callback)

@brief
Adds a text field
*/
int xutText(string label, ref string value, functor callback);

/**HELP_FUN
@decl
void aryAdd(ref type ary[ ], type value)

@brief
Adds a new element at the end of the array
*/
void aryAdd(ref type ary[ ], type value);

/**HELP_FUN
@decl
int arySize(ref type ary[ ])

@brief
Returns the number of elements in the array
*/
int arySize(ref type ary[ ]);

/**HELP_FUN
@decl
void aryClear(ref type ary[ ])

@brief
Removes all elements from the array
*/
void aryClear(ref type ary[ ]);
