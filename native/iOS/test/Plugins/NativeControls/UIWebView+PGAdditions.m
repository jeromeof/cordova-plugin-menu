//
//  UIWebview+PGAdditions.m

#import "UIWebView+PGAdditions.h"


NSComparisonResult sortByYPos(UIView* u1, UIView* u2, void* context) 
{
	if (u1.frame.origin.y == u2.frame.origin.y) { // same
		return NSOrderedSame;
	} else if (u1.frame.origin.y > u2.frame.origin.y) { // greater
		return NSOrderedDescending;
	} else { // lesser
		return NSOrderedAscending;
	}
}

@implementation UIWebView (PGLayoutAdditions)

/* For dynamically adding properties to an existing class (in this case UIWebView, 
   we need to pass a unique identifier, which is of type void*
   the easiest way for this is to pass the address of a static char, which guaranteed to be unique
 */
//static char nameKey; // CGRect

- (void) pg_addSiblingView:(UIView*) siblingView withPosition:(PGLayoutPosition)position withAnimation:(BOOL)animate
{
	NSAssert(siblingView.frame.size.height < self.frame.size.height, @"PhoneGap: Cannot add a sibling view that is larger than the UIWebView");

	CGRect siblingViewFrame = siblingView.frame;
	CGRect webViewFrame = self.frame;
	CGRect screenBounds = [[UIScreen mainScreen] bounds];
	
	NSEnumerator* enumerator = [self.superview.subviews objectEnumerator];
	UIView* subview;
	
	switch (position)
	{
		case PGLayoutPositionTop:
		{
			// shift down y-position of all sibling views by new view's height (only PGLayoutPositionTop items), 
			while ( (subview = [enumerator nextObject]) ) {
				if ([self pg_layoutPosition:subview] == PGLayoutPositionTop) {
					CGRect subviewFrame = subview.frame;
					subviewFrame.origin.y += siblingView.frame.size.height;
					subview.frame = subviewFrame;
				}
			}
			
			// webView is shrunk by new view's height (origin shift down as well)
			webViewFrame.origin.y += siblingView.frame.size.height;
			webViewFrame.size.height -= siblingView.frame.size.height;
			self.frame = webViewFrame;
			
			// make sure the siblingView's frame is to the top
			siblingViewFrame.origin.y = 0;
			siblingView.frame = siblingViewFrame;
		}
			break;
		case PGLayoutPositionBottom:
		{
			// shift up y-position of all sibling views by new view's height (only PGLayoutPositionBottom items), 
			while ( (subview = [enumerator nextObject]) ) {
				if ([self pg_layoutPosition:subview] == PGLayoutPositionBottom) {
					CGRect subviewFrame = subview.frame;
					subviewFrame.origin.y -= siblingView.frame.size.height;
					subview.frame = subviewFrame;
				}
			}
			
			// webView is shrunk by new view's height (no origin shift)
			webViewFrame.size.height -= siblingView.frame.size.height;
			self.frame = webViewFrame;
			
			// make sure the siblingView's frame is to the bottom
			siblingViewFrame.origin.y = screenBounds.size.height - siblingView.frame.size.height;
			siblingView.frame = siblingViewFrame;
		}
			break;
		default: // not specified, or unsupported, so we return
			return;
	}
	
	[self.superview addSubview:siblingView];
}

- (void) pg_moveSiblingView:(UIView*) siblingView toPosition:(PGLayoutPosition)position withAnimation:(BOOL)animate
{
	// this is essentially a remove, then add
	[self pg_removeSiblingView:siblingView withAnimation:animate];
	[self pg_relayout:animate];
	[self pg_addSiblingView:siblingView withPosition:position withAnimation:animate];
}

- (void) pg_removeSiblingView:(UIView*) siblingView withAnimation:(BOOL)animate
{
	// find the view in the superView hierarchy. we could use viewWithTag,
	// but this assumes callers have tagged their views (and we don't really want to tag management)
	// pg_relayout: needs to be called after to fill in the gap
	
	NSEnumerator* enumerator = [self.superview.subviews objectEnumerator];
	id subview;
	BOOL found = NO;
	
	while (subview = [enumerator nextObject]) {
		if (subview == siblingView) {
			found = YES;
		}
	}
	
	[siblingView removeFromSuperview];
}

- (CGSize) pg_totalViewDimensions:(NSMutableArray*)views
{
	NSEnumerator* enumerator = [views objectEnumerator];
	UIView* subview;
	CGSize size = CGSizeMake(0, 0);
	
	while (subview = [enumerator nextObject]) 
	{
		if (subview.hidden) {
			continue;
		}
		size.width += subview.frame.size.width;
		size.height += subview.frame.size.height;
	}
	
	return size;
}

- (void) pg_sortViews:(NSMutableArray*)views withOrigin:(CGPoint)origin
{
	// sort by y-position
	[views sortUsingFunction:sortByYPos context:nil];
	
	// now we fill in the gaps
	NSEnumerator* enumerator = [views objectEnumerator];
	UIView* subview;
	CGPoint nextOrigin = CGPointMake(origin.x, origin.y);
	
	while (subview = [enumerator nextObject]) 
	{
		if (subview.hidden) {
			continue;
		}
		
		CGRect subviewFrame = subview.frame;
		subviewFrame.origin.y = nextOrigin.y;
		subview.frame = subviewFrame;
		
		nextOrigin = CGPointMake(nextOrigin.x, (subviewFrame.origin.y + subviewFrame.size.height));
	}
}

- (void) pg_relayout:(BOOL)animate
{
	// check each sibling view, and re-size if necessary (UIWebview) (top to bottom)
	// first we partition, then move any intersecting (with UIWebView) to either the top, or bottom.
	// here we will choose the top
	
	CGRect screenBounds = [[UIScreen mainScreen] bounds];
	BOOL middleToTop = YES;
	
	UIView* centreView = self;
	
	NSMutableArray* top =		[NSMutableArray arrayWithCapacity:1];
	NSMutableArray* middle =	[NSMutableArray arrayWithCapacity:1];
	NSMutableArray* bottom =	[NSMutableArray arrayWithCapacity:1];
	
	NSEnumerator* enumerator = [self.superview.subviews objectEnumerator];
	UIView* subview;
	
	while (subview = [enumerator nextObject]) {
		if (subview.hidden) {
			continue;
		}
		
		if ([self pg_layoutPositionOfView:subview fromView:centreView] == PGLayoutPositionTop) {
			[top addObject:subview];
		} else if ([self pg_layoutPositionOfView:subview fromView:centreView] == PGLayoutPositionBottom) {
			[bottom addObject:subview];
		} else if (subview != self) { // it is in the "middle" check that it is not the UIWebView
			[middle addObject:subview];
		}
	}
	
	// Sort the Top, Middle, and Bottom Items.
	
	CGPoint nextOrigin = CGPointMake(0, 0);
	
	// sort Top items
	[self pg_sortViews:top withOrigin:nextOrigin];
	
	// get the last object from Top, to set the origin of Middle
	UIView* lastObject = [top lastObject];
	if (lastObject) {
		nextOrigin = CGPointMake(0, lastObject.frame.origin.y + lastObject.frame.size.height);
	}
	
	if (middleToTop) {
		// sort Middle items
		[self pg_sortViews:middle withOrigin:nextOrigin];
		lastObject = [middle lastObject];

		nextOrigin = CGPointMake(0, lastObject.frame.origin.y + lastObject.frame.size.height);
	} 
	
	// get the last object from Middle, to set the origin of centreView
	if (lastObject) {

		CGRect centreViewRect = centreView.frame;

		centreViewRect.origin.y = nextOrigin.y;
		
		// to calculate the height, we do (screenBounds - (topHeight + middleHeight + bottomHeight))
		centreViewRect.size.height = screenBounds.size.height - (
									[self pg_totalViewDimensions:top].height +
									[self pg_totalViewDimensions:middle].height +
									[self pg_totalViewDimensions:bottom].height);
		
		centreView.frame = centreViewRect;
		
		nextOrigin = CGPointMake(0, (centreViewRect.origin.y + centreViewRect.size.height));
	}
	
	if (!middleToTop) {
		// sort Middle items
		[self pg_sortViews:middle withOrigin:nextOrigin];
		lastObject = [middle lastObject];
		
		nextOrigin = CGPointMake(0, lastObject.frame.origin.y + lastObject.frame.size.height);
	} 
	
	// sort Bottom items
	[self pg_sortViews:bottom withOrigin:nextOrigin];
}

- (PGLayoutPosition) pg_layoutPositionOfView:(UIView*)siblingView fromView:(UIView*)fromView
{
	CGRect fromViewFrame = fromView.frame;
	CGRect siblingFrame = siblingView.frame;
	
	if (siblingFrame.origin.y > (fromViewFrame.origin.y + fromViewFrame.size.height)) 
	{
		return PGLayoutPositionBottom;
	} 
	else if (fromViewFrame.origin.y > (siblingFrame.origin.y + siblingFrame.size.height)) 
	{
		return PGLayoutPositionTop;
	} 
	else 
	{
		return PGLayoutPositionUnknown;
	}
}

- (PGLayoutPosition) pg_layoutPosition:(UIView*)siblingView
{
	return [self pg_layoutPositionOfView:siblingView fromView:self];
}

- (BOOL) pg_viewsAreIntersecting
{
	NSArray* subviews = self.superview.subviews; 
	NSInteger count = [subviews count];
	
	// for a low number of subviews, this algorithm is acceptable
	for (NSInteger i=0; i < count; ++i)
	{
		UIView* currentView = [subviews objectAtIndex:i];
		// check the current, with subsequent items
		for(NSInteger j=i+1; j < count; ++j)
		{
			UIView* nextView = [subviews objectAtIndex:j];
			if (CGRectIntersectsRect(currentView.frame, nextView.frame)) {
				return YES;
			}
		}
	}
	
	return NO;
}

@end
